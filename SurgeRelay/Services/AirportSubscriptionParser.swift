import Foundation

struct AirportProxyEntry: Equatable, Sendable {
    let originalName: String
    let definition: String
}

struct ProcessedAirportProxyEntry: Equatable, Sendable {
    let originalName: String
    let name: String
    let definition: String
}

struct AirportNodeProcessingRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { originalName }
    let originalName: String
    let outputName: String?
    let status: String
}

struct AirportNodeProcessingResult: Equatable, Sendable {
    let included: [ProcessedAirportProxyEntry]
    let records: [AirportNodeProcessingRecord]
}

enum AirportSubscriptionParser {
    static func proxyEntries(from data: Data) throws -> [AirportProxyEntry] {
        guard let initial = decodedText(data) else {
            throw RelayError.invalidOutput("订阅内容不是可识别的文本或 Base64 文本。")
        }
        var text = initial.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        // Some subscription providers wrap an already encoded response again.
        for _ in 0..<3 {
            guard let decoded = decodedBase64TextIfNeeded(text) else { break }
            text = decoded.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        }
        let lines = text.components(separatedBy: .newlines)
        let proxyLines: ArraySlice<String>

        if let proxyHeader = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[Proxy]" }) {
            let start = lines.index(after: proxyHeader)
            let end = lines[start...].firstIndex(where: {
                let value = $0.trimmingCharacters(in: .whitespaces)
                return value.hasPrefix("[") && value.hasSuffix("]")
            }) ?? lines.endIndex
            proxyLines = lines[start..<end]
        } else {
            proxyLines = lines[...]
        }

        var seen = Set<String>()
        let entries = try proxyLines.enumerated().compactMap { index, line -> AirportProxyEntry? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }
            // Dispatch URI lines before looking for '=' in query strings or Base64 padding.
            if trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil {
                let entry = try proxyEntry(fromURI: trimmed, lineNumber: index + 1)
                guard seen.insert(entry.originalName).inserted else { return nil }
                return entry
            }
            guard let equals = trimmed.firstIndex(of: "=") else { return nil }
            let rawName = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            let name = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let definition = String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
            let type = definition.split(separator: ",", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            let policyTypes: Set<String> = [
                "direct", "reject", "reject-tinygif", "reject-drop", "ss", "vmess", "trojan",
                "snell", "http", "https", "socks5", "socks5-tls", "h2-connect", "ssh",
                "tuic", "tuic-v5", "hysteria2", "anytls", "wireguard", "masque", "trust-tunnel", "external",
            ]
            guard !name.isEmpty, policyTypes.contains(type), seen.insert(name).inserted else { return nil }
            return AirportProxyEntry(originalName: name, definition: definition)
        }
        guard !entries.isEmpty else {
            throw RelayError.invalidOutput("订阅中没有找到可识别的代理节点，请使用 Surge 配置或 Base64 编码的 AnyTLS / Trojan 节点链接。")
        }
        return entries
    }

    /// Makes the common subscription metadata labels filterable with either
    /// their English source names or the Chinese terms users normally enter.
    static func name(_ name: String, matchesRegex pattern: String) -> Bool {
        var searchableName = name
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("traffic") { searchableName += " 流量" }
        if lowercaseName.contains("expire") || lowercaseName.contains("expiry") {
            searchableName += " 到期"
        }
        if lowercaseName.contains("reset") { searchableName += " 重置" }
        return searchableName.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func isBuiltInDirect(_ entry: AirportProxyEntry) -> Bool {
        guard entry.originalName.caseInsensitiveCompare("DIRECT") == .orderedSame else {
            return false
        }
        let policyType = entry.definition
            .split(separator: ",", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return policyType == "direct"
    }

    static func renamedNode(
        _ originalName: String,
        airportName: String,
        template: String,
        optimization: AirportNodeNameOptimization = AirportNodeNameOptimization()
    ) -> String {
        let optimizedName = optimizedNodeName(originalName, using: optimization)
        let template = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { return optimizedName }
        return template
            .replacingOccurrences(of: "{airport}", with: airportName)
            .replacingOccurrences(of: "{name}", with: optimizedName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func optimizedNodeName(
        _ originalName: String,
        using optimization: AirportNodeNameOptimization
    ) -> String {
        guard optimization.isEnabled else { return originalName }
        var name = optimization.smartCleanup ? intelligentlyCleanedNodeName(originalName) : originalName

        if optimization.removesEmoji {
            name.removeAll(where: isEmojiCharacter)
        }

        let terms = optimization.removalTerms
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for term in terms {
            name = name.replacingOccurrences(
                of: NSRegularExpression.escapedPattern(for: term),
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        name = name.replacingOccurrences(
            of: #"\[\s*\]|\(\s*\)|【\s*】|（\s*）"#,
            with: " ",
            options: .regularExpression
        )
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        name = name.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—_|/·•"))
        )
        return name.isEmpty ? "节点" : name
    }

    // Only remove redundant trailing region codes. Preserve rates and identifiers.
    static func intelligentlyCleanedNodeName(_ originalName: String) -> String {
        var name = originalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|｜/·•_-–—"))
        while true {
            let candidate = name.trimmingCharacters(in: separators)
            if let range = candidate.range(of: #"[\s|｜/·•_\-–—]+[a-z]{2}$"#, options: [.regularExpression, .caseInsensitive]) {
                let code = String(candidate.suffix(2)).uppercased()
                let prefix = String(candidate[..<range.lowerBound]).trimmingCharacters(in: separators)
                if isRedundantRegionCode(code, in: prefix) {
                    name = prefix
                    continue
                }
            }
            break
        }
        return name
    }

    private static func isRedundantRegionCode(_ code: String, in name: String) -> Bool {
        guard nodeRegionAliases[code] != nil else { return false }
        var strongestMatch = 0
        var matchingCodes = Set<String>()
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        for entry in nodeRegionPatterns {
            if entry.length < strongestMatch { break }
            guard entry.expression.firstMatch(in: name, range: range) != nil else { continue }
            if entry.length > strongestMatch {
                strongestMatch = entry.length
                matchingCodes = [entry.code]
            } else {
                matchingCodes.insert(entry.code)
            }
        }
        return matchingCodes == [code]
    }

    private static let nodeRegionPatterns: [(code: String, length: Int, expression: NSRegularExpression)] = {
        nodeRegionAliases.flatMap { code, aliases in
            aliases.compactMap { alias -> (code: String, length: Int, expression: NSRegularExpression)? in
                let escaped = NSRegularExpression.escapedPattern(for: alias)
                let pattern = alias.unicodeScalars.allSatisfy(\.isASCII)
                    ? #"(?i)(?<![a-z])"# + escaped + #"(?![a-z])"# : escaped
                guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
                return (code, alias.count, expression)
            }
        }.sorted { $0.length > $1.length }
    }()

    // Region names from Foundation locales zh_Hans, zh_Hant, zh_Hant_HK and en,
    // supplemented with common subscription aliases. Keep the Web table in sync.
    private static let nodeRegionAliases: [String: [String]] = [
        "AC": ["阿森松岛", "阿森松島", "Ascension Island", "AC"],
        "AD": ["安道尔", "安道爾", "Andorra", "AD"],
        "AE": ["阿拉伯联合酋长国", "阿拉伯聯合大公國", "阿拉伯聯合酋長國", "United Arab Emirates", "AE", "阿联酋", "阿聯酋"],
        "AF": ["阿富汗", "Afghanistan", "AF"],
        "AG": ["安提瓜和巴布达", "安地卡及巴布達", "安提瓜和巴布達", "Antigua & Barbuda", "AG"],
        "AI": ["安圭拉", "安奎拉", "Anguilla", "AI"],
        "AL": ["阿尔巴尼亚", "阿爾巴尼亞", "Albania", "AL"],
        "AM": ["亚美尼亚", "亞美尼亞", "Armenia", "AM"],
        "AO": ["安哥拉", "Angola", "AO"],
        "AQ": ["南极洲", "南極洲", "Antarctica", "AQ"],
        "AR": ["阿根廷", "Argentina", "AR"],
        "AS": ["美属萨摩亚", "美屬薩摩亞", "American Samoa", "AS"],
        "AT": ["奥地利", "奧地利", "Austria", "AT"],
        "AU": ["澳大利亚", "澳大利亞", "澳洲", "Australia", "AU"],
        "AW": ["阿鲁巴", "荷屬阿魯巴", "阿魯巴", "Aruba", "AW"],
        "AX": ["奥兰群岛", "奧蘭群島", "Åland Islands", "AX"],
        "AZ": ["阿塞拜疆", "亞塞拜然", "亞塞拜疆", "Azerbaijan", "AZ"],
        "BA": ["波斯尼亚和黑塞哥维那", "波士尼亞與赫塞哥維納", "波斯尼亞和黑塞哥維那", "Bosnia & Herzegovina", "BA", "波黑", "波黑共和国", "波黑共和國"],
        "BB": ["巴巴多斯", "巴貝多", "Barbados", "BB"],
        "BD": ["孟加拉国", "孟加拉", "Bangladesh", "BD", "孟加拉國"],
        "BE": ["比利时", "比利時", "Belgium", "BE"],
        "BF": ["布基纳法索", "布吉納法索", "布基納法索", "Burkina Faso", "BF"],
        "BG": ["保加利亚", "保加利亞", "Bulgaria", "BG"],
        "BH": ["巴林", "Bahrain", "BH"],
        "BI": ["布隆迪", "蒲隆地", "Burundi", "BI"],
        "BJ": ["贝宁", "貝南", "貝寧", "Benin", "BJ"],
        "BL": ["圣巴泰勒米", "聖巴瑟米", "聖巴泰勒米", "St. Barthélemy", "BL"],
        "BM": ["百慕大", "百慕達", "Bermuda", "BM"],
        "BN": ["文莱", "汶萊", "Brunei", "BN"],
        "BO": ["玻利维亚", "玻利維亞", "Bolivia", "BO"],
        "BQ": ["荷属加勒比区", "荷蘭加勒比區", "Caribbean Netherlands", "BQ"],
        "BR": ["巴西", "Brazil", "BR"],
        "BS": ["巴哈马", "巴哈馬", "Bahamas", "BS"],
        "BT": ["不丹", "Bhutan", "BT"],
        "BV": ["布韦岛", "布威島", "鮑威特島", "Bouvet Island", "BV"],
        "BW": ["博茨瓦纳", "波札那", "博茨瓦納", "Botswana", "BW"],
        "BY": ["白俄罗斯", "白俄羅斯", "Belarus", "BY"],
        "BZ": ["伯利兹", "貝里斯", "伯利茲", "Belize", "BZ"],
        "CA": ["加拿大", "Canada", "CA"],
        "CC": ["科科斯（基林）群岛", "科克斯（基靈）群島", "科科斯（基林）群島", "Cocos (Keeling) Islands", "CC"],
        "CD": ["刚果（金）", "剛果（金夏沙）", "Congo - Kinshasa", "CD"],
        "CF": ["中非共和国", "中非共和國", "Central African Republic", "CF"],
        "CG": ["刚果（布）", "剛果（布拉薩）", "Congo - Brazzaville", "CG"],
        "CH": ["瑞士", "Switzerland", "CH"],
        "CI": ["科特迪瓦", "象牙海岸", "Côte d’Ivoire", "CI"],
        "CK": ["库克群岛", "庫克群島", "Cook Islands", "CK"],
        "CL": ["智利", "Chile", "CL"],
        "CM": ["喀麦隆", "喀麥隆", "Cameroon", "CM"],
        "CN": ["中国大陆", "中國大陸", "China mainland", "CN"],
        "CO": ["哥伦比亚", "哥倫比亞", "Colombia", "CO"],
        "CP": ["克利珀顿岛", "克里派頓島", "克里珀頓島", "Clipperton Island", "CP"],
        "CQ": ["萨克岛", "薩克島", "Sark", "CQ"],
        "CR": ["哥斯达黎加", "哥斯大黎加", "哥斯達黎加", "Costa Rica", "CR"],
        "CU": ["古巴", "Cuba", "CU"],
        "CV": ["佛得角", "維德角", "Cape Verde", "CV"],
        "CW": ["库拉索", "庫拉索", "Curaçao", "CW"],
        "CX": ["圣诞岛", "聖誕島", "Christmas Island", "CX"],
        "CY": ["塞浦路斯", "Cyprus", "CY", "賽普勒斯"],
        "CZ": ["捷克", "Czechia", "Czech Republic", "CZ"],
        "DE": ["德国", "德國", "Germany", "DE"],
        "DG": ["迪戈加西亚岛", "迪亞哥加西亞島", "Diego Garcia", "DG"],
        "DJ": ["吉布提", "吉布地", "Djibouti", "DJ"],
        "DK": ["丹麦", "丹麥", "Denmark", "DK"],
        "DM": ["多米尼克", "Dominica", "DM"],
        "DO": ["多米尼加共和国", "多明尼加共和國", "多米尼加共和國", "Dominican Republic", "DO", "多米尼加"],
        "DZ": ["阿尔及利亚", "阿爾及利亞", "Algeria", "DZ"],
        "EA": ["休达及梅利利亚", "休達與梅利利亞", "Ceuta & Melilla", "EA"],
        "EC": ["厄瓜多尔", "厄瓜多", "厄瓜多爾", "Ecuador", "EC"],
        "EE": ["爱沙尼亚", "愛沙尼亞", "Estonia", "EE"],
        "EG": ["埃及", "Egypt", "EG"],
        "EH": ["西撒哈拉", "Western Sahara", "EH"],
        "ER": ["厄立特里亚", "厄利垂亞", "厄立特里亞", "Eritrea", "ER"],
        "ES": ["西班牙", "Spain", "ES"],
        "ET": ["埃塞俄比亚", "衣索比亞", "埃塞俄比亞", "Ethiopia", "ET"],
        "EU": ["欧盟", "歐盟", "European Union", "EU"],
        "EZ": ["欧元区", "歐元區", "Eurozone", "EZ"],
        "FI": ["芬兰", "芬蘭", "Finland", "FI"],
        "FJ": ["斐济", "斐濟", "Fiji", "FJ"],
        "FK": ["福克兰群岛", "福克蘭群島", "Falkland Islands", "FK"],
        "FM": ["密克罗尼西亚", "密克羅尼西亞", "Micronesia", "FM"],
        "FO": ["法罗群岛", "法羅群島", "Faroe Islands", "FO"],
        "FR": ["法国", "法國", "France", "FR"],
        "GA": ["加蓬", "加彭", "Gabon", "GA"],
        "GB": ["英国", "英國", "United Kingdom", "UK", "GB"],
        "GD": ["格林纳达", "格瑞那達", "格林納達", "Grenada", "GD"],
        "GE": ["格鲁吉亚", "格魯吉亞", "Georgia", "GE", "喬治亞"],
        "GF": ["法属圭亚那", "法屬圭亞那", "French Guiana", "GF"],
        "GG": ["根西岛", "根息", "Guernsey", "GG"],
        "GH": ["加纳", "迦納", "加納", "Ghana", "GH"],
        "GI": ["直布罗陀", "直布羅陀", "Gibraltar", "GI"],
        "GL": ["格陵兰", "格陵蘭", "Greenland", "GL"],
        "GM": ["冈比亚", "甘比亞", "岡比亞", "Gambia", "GM"],
        "GN": ["几内亚", "幾內亞", "Guinea", "GN"],
        "GP": ["瓜德罗普", "瓜地洛普", "Guadeloupe", "GP"],
        "GQ": ["赤道几内亚", "赤道幾內亞", "Equatorial Guinea", "GQ"],
        "GR": ["希腊", "希臘", "Greece", "GR"],
        "GS": ["南乔治亚和南桑威奇群岛", "南喬治亞與南三明治群島", "南佐治亞島與南桑威奇群島", "So. Georgia & So. Sandwich Isl.", "GS"],
        "GT": ["危地马拉", "瓜地馬拉", "危地馬拉", "Guatemala", "GT"],
        "GU": ["关岛", "關島", "Guam", "GU"],
        "GW": ["几内亚比绍", "幾內亞比索", "幾內亞比紹", "Guinea-Bissau", "GW"],
        "GY": ["圭亚那", "蓋亞那", "圭亞那", "Guyana", "GY"],
        "HK": ["香港", "Hong Kong", "HK"],
        "HM": ["赫德岛和麦克唐纳群岛", "赫德島及麥唐納群島", "Heard & McDonald Islands", "HM"],
        "HN": ["洪都拉斯", "宏都拉斯", "Honduras", "HN"],
        "HR": ["克罗地亚", "克羅埃西亞", "克羅地亞", "Croatia", "HR"],
        "HT": ["海地", "Haiti", "HT"],
        "HU": ["匈牙利", "Hungary", "HU"],
        "IC": ["加纳利群岛", "加那利群島", "Canary Islands", "IC"],
        "ID": ["印尼", "印度尼西亚", "印度尼西亞", "Indonesia", "ID"],
        "IE": ["爱尔兰", "愛爾蘭", "Ireland", "IE"],
        "IL": ["以色列", "Israel", "IL"],
        "IM": ["马恩岛", "曼島", "馬恩島", "Isle of Man", "IM"],
        "IN": ["印度", "India", "IN"],
        "IO": ["查戈斯群岛", "查戈斯群島", "Chagos Archipelago", "IO"],
        "IQ": ["伊拉克", "Iraq", "IQ"],
        "IR": ["伊朗", "Iran", "IR"],
        "IS": ["冰岛", "冰島", "Iceland", "IS"],
        "IT": ["意大利", "義大利", "Italy", "IT"],
        "JE": ["泽西岛", "澤西島", "Jersey", "JE"],
        "JM": ["牙买加", "牙買加", "Jamaica", "JM"],
        "JO": ["约旦", "約旦", "Jordan", "JO"],
        "JP": ["日本", "Japan", "JP"],
        "KE": ["肯尼亚", "肯亞", "肯尼亞", "Kenya", "KE"],
        "KG": ["吉尔吉斯斯坦", "吉爾吉斯", "Kyrgyzstan", "KG"],
        "KH": ["柬埔寨", "Cambodia", "KH"],
        "KI": ["基里巴斯", "吉里巴斯", "Kiribati", "KI"],
        "KM": ["科摩罗", "葛摩", "科摩羅", "Comoros", "KM"],
        "KN": ["圣基茨和尼维斯", "聖克里斯多福及尼維斯", "聖基茨和尼維斯", "St. Kitts & Nevis", "KN"],
        "KP": ["朝鲜", "北韓", "North Korea", "KP"],
        "KR": ["韩国", "韓國", "Korea", "KR", "南韓", "South Korea"],
        "KW": ["科威特", "Kuwait", "KW"],
        "KY": ["开曼群岛", "開曼群島", "Cayman Islands", "KY"],
        "KZ": ["哈萨克斯坦", "哈薩克", "Kazakhstan", "KZ"],
        "LA": ["老挝", "寮國", "老撾", "Laos", "LA"],
        "LB": ["黎巴嫩", "Lebanon", "LB"],
        "LC": ["圣卢西亚", "聖露西亞", "聖盧西亞", "St. Lucia", "LC"],
        "LI": ["列支敦士登", "列支敦斯登", "Liechtenstein", "LI"],
        "LK": ["斯里兰卡", "斯里蘭卡", "Sri Lanka", "LK"],
        "LR": ["利比里亚", "賴比瑞亞", "利比里亞", "Liberia", "LR"],
        "LS": ["莱索托", "賴索托", "萊索托", "Lesotho", "LS"],
        "LT": ["立陶宛", "Lithuania", "LT"],
        "LU": ["卢森堡", "盧森堡", "Luxembourg", "LU"],
        "LV": ["拉脱维亚", "拉脫維亞", "Latvia", "LV"],
        "LY": ["利比亚", "利比亞", "Libya", "LY"],
        "MA": ["摩洛哥", "Morocco", "MA"],
        "MC": ["摩纳哥", "摩納哥", "Monaco", "MC"],
        "MD": ["摩尔多瓦", "摩爾多瓦", "Moldova", "MD"],
        "ME": ["黑山", "蒙特內哥羅", "Montenegro", "ME"],
        "MF": ["法属圣马丁", "法屬聖馬丁", "St. Martin", "MF"],
        "MG": ["马达加斯加", "馬達加斯加", "Madagascar", "MG"],
        "MH": ["马绍尔群岛", "馬紹爾群島", "Marshall Islands", "MH"],
        "MK": ["北马其顿", "北馬其頓", "North Macedonia", "MK"],
        "ML": ["马里", "馬利", "馬里", "Mali", "ML"],
        "MM": ["缅甸", "緬甸", "Myanmar (Burma)", "MM"],
        "MN": ["蒙古", "Mongolia", "MN"],
        "MO": ["澳门", "澳門", "Macau", "Macao", "MO"],
        "MP": ["北马里亚纳群岛", "北馬利安納群島", "Northern Mariana Islands", "MP"],
        "MQ": ["马提尼克", "馬丁尼克", "Martinique", "MQ"],
        "MR": ["毛里塔尼亚", "茅利塔尼亞", "毛里塔尼亞", "Mauritania", "MR"],
        "MS": ["蒙特塞拉特", "蒙哲臘", "Montserrat", "MS"],
        "MT": ["马耳他", "馬爾他", "馬耳他", "Malta", "MT"],
        "MU": ["毛里求斯", "模里西斯", "毛里裘斯", "Mauritius", "MU"],
        "MV": ["马尔代夫", "馬爾地夫", "馬爾代夫", "Maldives", "MV"],
        "MW": ["马拉维", "馬拉威", "馬拉維", "Malawi", "MW"],
        "MX": ["墨西哥", "Mexico", "MX"],
        "MY": ["马来西亚", "馬來西亞", "Malaysia", "MY"],
        "MZ": ["莫桑比克", "莫三比克", "Mozambique", "MZ"],
        "NA": ["纳米比亚", "納米比亞", "Namibia", "NA"],
        "NC": ["新喀里多尼亚", "新喀里多尼亞", "New Caledonia", "NC"],
        "NE": ["尼日尔", "尼日", "尼日爾", "Niger", "NE"],
        "NF": ["诺福克岛", "諾福克島", "Norfolk Island", "NF"],
        "NG": ["尼日利亚", "奈及利亞", "尼日利亞", "Nigeria", "NG"],
        "NI": ["尼加拉瓜", "Nicaragua", "NI"],
        "NL": ["荷兰", "荷蘭", "Netherlands", "NL"],
        "NO": ["挪威", "Norway", "NO"],
        "NP": ["尼泊尔", "尼泊爾", "Nepal", "NP"],
        "NR": ["瑙鲁", "諾魯", "瑙魯", "Nauru", "NR"],
        "NU": ["纽埃", "紐埃島", "Niue", "NU"],
        "NZ": ["新西兰", "紐西蘭", "New Zealand", "NZ"],
        "OM": ["阿曼", "Oman", "OM"],
        "PA": ["巴拿马", "巴拿馬", "Panama", "PA"],
        "PE": ["秘鲁", "秘魯", "Peru", "PE"],
        "PF": ["法属波利尼西亚", "法屬玻里尼西亞", "法屬波利尼西亞", "French Polynesia", "PF"],
        "PG": ["巴布亚新几内亚", "巴布亞紐幾內亞", "巴布亞新畿內亞", "Papua New Guinea", "PG"],
        "PH": ["菲律宾", "菲律賓", "Philippines", "PH"],
        "PK": ["巴基斯坦", "Pakistan", "PK"],
        "PL": ["波兰", "波蘭", "Poland", "PL"],
        "PM": ["圣皮埃尔和密克隆群岛", "聖皮埃與密克隆群島", "St. Pierre & Miquelon", "PM"],
        "PN": ["皮特凯恩群岛", "皮特肯群島", "皮特凱恩島", "Pitcairn Islands", "PN"],
        "PR": ["波多黎各", "Puerto Rico", "PR"],
        "PS": ["巴勒斯坦领土", "巴勒斯坦自治區", "巴勒斯坦領土", "Palestinian Territories", "PS", "巴勒斯坦"],
        "PT": ["葡萄牙", "Portugal", "PT"],
        "PW": ["帕劳", "帛琉", "Palau", "PW"],
        "PY": ["巴拉圭", "Paraguay", "PY"],
        "QA": ["卡塔尔", "卡達", "卡塔爾", "Qatar", "QA"],
        "QO": ["大洋洲边远群岛", "大洋洲邊疆群島", "Outlying Oceania", "QO"],
        "RE": ["留尼汪", "留尼旺", "Réunion", "RE"],
        "RO": ["罗马尼亚", "羅馬尼亞", "Romania", "RO"],
        "RS": ["塞尔维亚", "塞爾維亞", "Serbia", "RS"],
        "RU": ["俄罗斯", "俄羅斯", "Russia", "RU"],
        "RW": ["卢旺达", "盧安達", "盧旺達", "Rwanda", "RW"],
        "SA": ["沙特阿拉伯", "沙烏地阿拉伯", "沙地阿拉伯", "Saudi Arabia", "SA"],
        "SB": ["所罗门群岛", "索羅門群島", "所羅門群島", "Solomon Islands", "SB"],
        "SC": ["塞舌尔", "塞席爾", "塞舌爾", "Seychelles", "SC"],
        "SD": ["苏丹", "蘇丹", "Sudan", "SD"],
        "SE": ["瑞典", "Sweden", "SE"],
        "SG": ["新加坡", "狮城", "獅城", "Singapore", "SG"],
        "SH": ["圣赫勒拿", "聖赫勒拿島", "St. Helena", "SH"],
        "SI": ["斯洛文尼亚", "斯洛維尼亞", "斯洛文尼亞", "Slovenia", "SI"],
        "SJ": ["斯瓦尔巴和扬马延", "挪威屬斯瓦巴及尖棉", "斯瓦爾巴特群島及揚馬延島", "Svalbard & Jan Mayen", "SJ"],
        "SK": ["斯洛伐克", "Slovakia", "SK"],
        "SL": ["塞拉利昂", "獅子山共和國", "Sierra Leone", "SL"],
        "SM": ["圣马力诺", "聖馬利諾", "聖馬力諾", "San Marino", "SM"],
        "SN": ["塞内加尔", "塞內加爾", "Senegal", "SN"],
        "SO": ["索马里", "索馬利亞", "索馬里", "Somalia", "SO"],
        "SR": ["苏里南", "蘇利南", "蘇里南", "Suriname", "SR"],
        "SS": ["南苏丹", "南蘇丹", "South Sudan", "SS"],
        "ST": ["圣多美和普林西比", "聖多美普林西比", "聖多美和普林西比", "São Tomé & Príncipe", "ST"],
        "SV": ["萨尔瓦多", "薩爾瓦多", "El Salvador", "SV"],
        "SX": ["荷属圣马丁", "荷屬聖馬丁", "Sint Maarten", "SX"],
        "SY": ["叙利亚", "敘利亞", "Syria", "SY"],
        "SZ": ["斯威士兰", "史瓦帝尼", "斯威士蘭", "Eswatini", "SZ"],
        "TA": ["特里斯坦-达库尼亚群岛", "特里斯坦達庫尼亞群島", "Tristan da Cunha", "TA"],
        "TC": ["特克斯和凯科斯群岛", "土克斯及開科斯群島", "特克斯和凱科斯群島", "Turks & Caicos Islands", "TC"],
        "TD": ["乍得", "查德", "Chad", "TD"],
        "TF": ["法属南部领地", "法屬南部屬地", "法屬南部領地", "French Southern Territories", "TF"],
        "TG": ["多哥", "Togo", "TG"],
        "TH": ["泰国", "泰國", "Thailand", "TH"],
        "TJ": ["塔吉克斯坦", "塔吉克", "Tajikistan", "TJ"],
        "TK": ["托克劳", "托克勞群島", "Tokelau", "TK"],
        "TL": ["东帝汶", "東帝汶", "Timor-Leste", "TL"],
        "TM": ["土库曼斯坦", "土庫曼", "Turkmenistan", "TM"],
        "TN": ["突尼斯", "突尼西亞", "Tunisia", "TN"],
        "TO": ["汤加", "東加", "湯加", "Tonga", "TO"],
        "TR": ["土耳其", "Turkey", "Türkiye", "TR"],
        "TT": ["特立尼达和多巴哥", "千里達及托巴哥", "千里達和多巴哥", "Trinidad & Tobago", "TT"],
        "TV": ["图瓦卢", "吐瓦魯", "圖瓦盧", "Tuvalu", "TV"],
        "TW": ["台湾", "台灣", "Taiwan", "TW"],
        "TZ": ["坦桑尼亚", "坦尚尼亞", "坦桑尼亞", "Tanzania", "TZ"],
        "UA": ["乌克兰", "烏克蘭", "Ukraine", "UA"],
        "UG": ["乌干达", "烏干達", "Uganda", "UG"],
        "UM": ["美国本土外小岛屿", "美國本土外小島嶼", "U.S. Outlying Islands", "UM"],
        "UN": ["联合国", "聯合國", "United Nations", "UN"],
        "US": ["美国", "美國", "United States", "USA", "US"],
        "UY": ["乌拉圭", "烏拉圭", "Uruguay", "UY"],
        "UZ": ["乌兹别克斯坦", "烏茲別克斯坦", "Uzbekistan", "UZ", "烏茲別克"],
        "VA": ["梵蒂冈", "梵蒂岡", "Vatican City", "VA"],
        "VC": ["圣文森特和格林纳丁斯", "聖文森及格瑞那丁", "聖文森特和格林納丁斯", "St. Vincent & Grenadines", "VC"],
        "VE": ["委内瑞拉", "委內瑞拉", "Venezuela", "VE"],
        "VG": ["英属维尔京群岛", "英屬維京群島", "英屬維爾京群島", "British Virgin Islands", "VG"],
        "VI": ["美属维尔京群岛", "美屬維京群島", "美屬維爾京群島", "U.S. Virgin Islands", "VI"],
        "VN": ["越南", "Vietnam", "VN"],
        "VU": ["瓦努阿图", "萬那杜", "瓦努阿圖", "Vanuatu", "VU"],
        "WF": ["瓦利斯和富图纳", "瓦利斯群島和富圖那群島", "Wallis & Futuna", "WF"],
        "WS": ["萨摩亚", "薩摩亞", "Samoa", "WS"],
        "XK": ["科索沃", "Kosovo", "XK"],
        "YE": ["也门", "葉門", "也門", "Yemen", "YE"],
        "YT": ["马约特", "馬約特島", "馬約特", "Mayotte", "YT"],
        "ZA": ["南非", "South Africa", "ZA"],
        "ZM": ["赞比亚", "尚比亞", "贊比亞", "Zambia", "ZM"],
        "ZW": ["津巴布韦", "辛巴威", "津巴布韋", "Zimbabwe", "ZW"]
    ]

    static func uniqueNodeName(_ preferredName: String, reserving usedNames: inout Set<String>) -> String {
        if usedNames.insert(preferredName.lowercased()).inserted {
            return preferredName
        }
        var index = 2
        while true {
            let candidate = "\(preferredName) \(index)"
            if usedNames.insert(candidate.lowercased()).inserted {
                return candidate
            }
            index += 1
        }
    }

    static func process(
        _ entries: [AirportProxyEntry],
        for subscription: AirportSubscription,
        reserving usedNames: inout Set<String>
    ) -> AirportNodeProcessingResult {
        let includeKeywords = normalizedKeywords(subscription.nodeProcessing.includeKeywords)
        let excludeKeywords = normalizedKeywords(subscription.nodeProcessing.excludeKeywords)
        let priorityKeywords = normalizedKeywords(subscription.nodeProcessing.sortPriorityKeywords)
        let regex = subscription.policyRegexFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [(index: Int, entry: AirportProxyEntry, preferredName: String)] = []
        var excludedRecords: [AirportNodeProcessingRecord] = []

        for (index, entry) in entries.enumerated() {
            let exclusionReason: String? = if isBuiltInDirect(entry) {
                "内置策略"
            } else if subscription.nodeProcessing.filtersMetadataNodes,
                      isSubscriptionMetadataName(entry.originalName) {
                "订阅信息"
            } else if !includeKeywords.isEmpty,
                      !containsAnyKeyword(entry.originalName, keywords: includeKeywords) {
                "不符合保留规则"
            } else if containsAnyKeyword(entry.originalName, keywords: excludeKeywords) {
                "命中排除规则"
            } else if !regex.isEmpty, !name(entry.originalName, matchesRegex: regex) {
                "未通过高级正则"
            } else {
                nil
            }

            if let exclusionReason {
                excludedRecords.append(AirportNodeProcessingRecord(
                    originalName: entry.originalName,
                    outputName: nil,
                    status: exclusionReason
                ))
                continue
            }

            let preferredName = renamedNode(
                entry.originalName,
                airportName: subscription.trimmedName,
                template: subscription.nodeNameTemplate,
                optimization: subscription.nodeNameOptimization
            )
            candidates.append((index, entry, preferredName))
        }

        switch subscription.nodeProcessing.sortOrder {
        case .original:
            break
        case .nameAscending:
            candidates.sort { lhs, rhs in
                let comparison = lhs.preferredName.localizedStandardCompare(rhs.preferredName)
                return comparison == .orderedSame ? lhs.index < rhs.index : comparison == .orderedAscending
            }
        case .nameDescending:
            candidates.sort { lhs, rhs in
                let comparison = lhs.preferredName.localizedStandardCompare(rhs.preferredName)
                return comparison == .orderedSame ? lhs.index < rhs.index : comparison == .orderedDescending
            }
        case .keywordPriority:
            candidates.sort { lhs, rhs in
                let lhsPriority = priorityIndex(for: lhs.preferredName, keywords: priorityKeywords)
                let rhsPriority = priorityIndex(for: rhs.preferredName, keywords: priorityKeywords)
                return lhsPriority == rhsPriority ? lhs.index < rhs.index : lhsPriority < rhsPriority
            }
        }

        var included: [ProcessedAirportProxyEntry] = []
        var includedRecords: [AirportNodeProcessingRecord] = []
        included.reserveCapacity(candidates.count)
        includedRecords.reserveCapacity(candidates.count)
        for candidate in candidates {
            let outputName = uniqueNodeName(candidate.preferredName, reserving: &usedNames)
            let definition = applyingProxyOverrides(
                to: candidate.entry.definition,
                options: subscription.nodeProcessing
            )
            included.append(ProcessedAirportProxyEntry(
                originalName: candidate.entry.originalName,
                name: outputName,
                definition: definition
            ))
            includedRecords.append(AirportNodeProcessingRecord(
                originalName: candidate.entry.originalName,
                outputName: outputName,
                status: outputName == candidate.entry.originalName ? "保留" : "已优化"
            ))
        }

        return AirportNodeProcessingResult(
            included: included,
            records: includedRecords + excludedRecords
        )
    }

    static func isSubscriptionMetadataName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        let keywords = [
            "traffic", "bandwidth", "expire", "expiry", "reset", "official website",
            "流量", "剩余", "到期", "过期", "重置", "官网", "网址", "套餐", "应急", "更新时间",
        ]
        return keywords.contains { normalized.contains($0) }
    }

    private static func normalizedKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private static func containsAnyKeyword(_ name: String, keywords: [String]) -> Bool {
        keywords.contains { keyword in
            name.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func priorityIndex(for name: String, keywords: [String]) -> Int {
        keywords.firstIndex { keyword in
            name.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        } ?? keywords.count
    }

    private static func applyingProxyOverrides(
        to definition: String,
        options: AirportNodeProcessingOptions
    ) -> String {
        var tokens = commaSeparatedTokens(in: definition)
        guard let proxyType = tokens.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return definition
        }

        let udpTypes: Set<String> = [
            "ss", "vmess", "trojan", "snell", "socks5", "socks5-tls", "masque", "wireguard",
        ]
        let certificateTypes: Set<String> = [
            "vmess", "trojan", "https", "h2-connect", "socks5-tls", "tuic", "tuic-v5", "anytls",
            "trust-tunnel", "masque", "wireguard",
        ]

        if udpTypes.contains(proxyType), let value = options.udpRelay.boolValue {
            replaceOption(in: &tokens, aliases: ["udp-relay"], key: "udp-relay", value: value)
        }
        if let value = options.tcpFastOpen.boolValue {
            replaceOption(in: &tokens, aliases: ["tfo", "fast-open"], key: "tfo", value: value)
        }
        if certificateTypes.contains(proxyType), let value = options.skipCertificateVerification.boolValue {
            replaceOption(
                in: &tokens,
                aliases: ["skip-cert-verify"],
                key: "skip-cert-verify",
                value: value
            )
        }
        return tokens.joined(separator: ", ")
    }

    private static func replaceOption(
        in tokens: inout [String],
        aliases: Set<String>,
        key: String,
        value: Bool
    ) {
        tokens.removeAll { token in
            guard let equals = token.firstIndex(of: "=") else { return false }
            let existingKey = token[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return aliases.contains(existingKey)
        }
        tokens.append("\(key)=\(value ? "true" : "false")")
    }

    private static func commaSeparatedTokens(in value: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        var isEscaped = false

        for character in value {
            if isEscaped {
                token.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                token.append(character)
                isEscaped = true
                continue
            }
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                token.append(character)
                continue
            }
            if character == ",", quote == nil {
                tokens.append(token.trimmingCharacters(in: .whitespacesAndNewlines))
                token = ""
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty || !tokens.isEmpty {
            tokens.append(token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return tokens.filter { !$0.isEmpty }
    }

    private static func isEmojiCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let value = scalar.value
            return scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && value >= 0x1F000)
                || (0x1F1E6...0x1F1FF).contains(value)
                || (0x1F3FB...0x1F3FF).contains(value)
                || value == 0xFE0F
                || value == 0x200D
        }
    }

    private static func decodedText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func decodedBase64TextIfNeeded(_ text: String) -> String? {
        var compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !compact.isEmpty else { return nil }
        compact += String(repeating: "=", count: (4 - compact.count % 4) % 4)
        guard let data = Data(base64Encoded: compact),
              let decoded = String(data: data, encoding: .utf8),
              !decoded.isEmpty else { return nil }
        return decoded
    }

    private static func proxyEntry(fromURI text: String, lineNumber: Int) throws -> AirportProxyEntry {
        func invalid(_ reason: String) -> RelayError {
            // Never include the original URI: it contains subscription credentials.
            .invalidOutput("订阅第 \(lineNumber) 行：\(reason)")
        }
        // Normalize raw Unicode without re-encoding existing % escapes. Foundation's
        // automatic repair otherwise turns mixed "香港%2001" into "香港%252001".
        let uriCharacters = CharacterSet.urlFragmentAllowed.union(CharacterSet(charactersIn: "%#[]"))
        guard let encodedURI = text.addingPercentEncoding(withAllowedCharacters: uriCharacters),
              let url = URLComponents(string: encodedURI), let scheme = url.scheme?.lowercased() else {
            throw invalid("节点链接无效。")
        }
        guard ["anytls", "trojan"].contains(scheme) else {
            throw invalid("暂不支持 \(scheme) 节点链接，请向服务商获取 Surge 格式订阅。")
        }
        guard let host = url.host, !host.isEmpty,
              let port = url.port, (1...65535).contains(port),
              let user = url.user, !user.isEmpty else {
            throw invalid("节点缺少服务器、有效端口或密码。")
        }
        func quotedValue(_ value: String) throws -> String {
            guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw invalid("节点参数包含控制字符。")
            }
            return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let password = user + (url.password.map { ":" + $0 } ?? "")
        var tokens = [scheme, try quotedValue(host), String(port), "password=\(try quotedValue(password))"]
        for item in url.queryItems ?? [] {
            let key = item.name.lowercased()
            let value = item.value ?? ""
            switch key {
            case "sni", "peer", "alpn":
                if !value.isEmpty {
                    tokens.append("\(key == "peer" ? "sni" : key)=\(try quotedValue(value))")
                }
            case "insecure", "allowinsecure", "skip-cert-verify":
                guard ["0", "1", "true", "false"].contains(value.lowercased()) else {
                    throw invalid("证书验证参数无效。")
                }
                tokens.append("skip-cert-verify=\(["1", "true"].contains(value.lowercased()) ? "true" : "false")")
            case "type", "security":
                guard value.isEmpty || (key == "type" ? value == "tcp" : value == "tls") else {
                    throw invalid("暂不支持该节点传输方式，请使用 Surge 格式订阅。")
                }
            default:
                throw invalid("节点包含暂不支持的参数，请使用 Surge 格式订阅。")
            }
        }
        let originalName = url.fragment.flatMap { $0.isEmpty ? nil : $0 } ?? "\(scheme)-\(host)-\(port)"
        // Names are written on the left of '=' and referenced in comma-separated groups.
        let name = originalName.components(separatedBy: .controlCharacters).joined(separator: " ")
            .replacingOccurrences(of: ",", with: "，")
            .replacingOccurrences(of: "=", with: "＝")
            .replacingOccurrences(of: "\"", with: "＂")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AirportProxyEntry(originalName: name.isEmpty ? "节点 \(lineNumber)" : name, definition: tokens.joined(separator: ", "))
    }
}
