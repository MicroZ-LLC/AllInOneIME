import Foundation

/// The words the key detector (`Redaction.isOrdinary`) knows: a string made mostly of them is text, not a key.
enum RedactionWords {
    /// English words: the system's word list (/usr/share/dict/words, Webster's), lowercased, read once when first
    /// needed; with the few endings it leaves out (`isEnglish`).
    static let english: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        var words = Set<String>()
        for line in text.split(separator: "\n") where line.count >= 3 { words.insert(line.lowercased()) }
        return words
    }()

    /// Whether `word` (lowercased) is an English word, or one with -s, -es, -ed, -ing, -er, -ers, -ly, -ies, -ied added.
    static func isEnglish(_ word: String) -> Bool {
        if english.contains(word) || tech.contains(word) { return true }
        for (ending, base) in [("ies", "y"), ("ied", "y"), ("ing", ""), ("ing", "e"), ("ers", ""), ("ers", "e"), ("es", ""), ("ed", ""),
                               ("ed", "e"), ("er", ""), ("er", "e"), ("ly", ""), ("s", "")] where word.hasSuffix(ending) && word.count > ending.count + 2 {
            let stem = String(word.dropLast(ending.count)) + base
            if english.contains(stem) || tech.contains(stem) { return true }
            // A consonant doubled before the ending: "formatter", "running".
            if base.isEmpty, let last = stem.last, stem.dropLast().last == last, english.contains(String(stem.dropLast())) { return true }
        }
        return false
    }

    /// Whether `word` (lowercased) is a known word, or two joined, each of four letters or more ("acmecorp").
    static func isWordOrPair(_ word: String) -> Bool {
        if isEnglish(word) { return true }
        guard word.count >= 8 else { return false }
        return (4...(word.count - 4)).contains { cut in
            isEnglish(String(word.prefix(cut))) && isEnglish(String(word.dropFirst(cut)))
        }
    }

    /// The syllables of Mandarin pinyin, without tones (from the system's own transliteration of Chinese characters).
    static let pinyin: Set<String> = Set((
        "a ai an ang ao ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu ca cai can cang cao ce cen "
        + "ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong "
        + "cou cu cuan cui cun cuo da dai dan dang dao de den deng di dia dian diao die ding diu dong dou du duan dui dun "
        + "duo e ei en eng er fa fan fang fei fen feng fiao fo fou fu ga gai gan gang gao ge gei gen geng gong gou gu gua "
        + "guai guan guang gui gun guo ha hai han hang hao he hei hen heng hm hong hou hu hua huai huan huang hui hun huo "
        + "ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun ka kai kan kang kao ke kei ken keng kong kou ku "
        + "kua kuai kuan kuang kui kun kuo la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo "
        + "long lou lu luan lue lun luo lv lve m ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou "
        + "mu na nai nan nang nao ne nei nen neng ng ni nian niang niao nie nin ning niu nong nou nu nuan nue nun nuo nv "
        + "nve o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu qi qia qian qiang qiao qie qin "
        + "qing qiong qiu qu quan que qun ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo sa sai san sang "
        + "sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun "
        + "shuo si song sou su suan sui sun suo ta tai tan tang tao te teng ti tian tiao tie ting tong tou tu tuan tui "
        + "tun tuo wa wai wan wang wei wen weng wo wu xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun ya "
        + "yan yang yao ye yi yin ying yo yong you yu yuan yue yun za zai zan zang zao ze zei zen zeng zha zhai zhan "
        + "zhang zhao zhe zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui "
        + "zun zuo"
    ).split(separator: " ").map(String.init))

    /// Words of computing the system's list doesn't have: acronyms, formats, versions, architectures.
    static let tech: Set<String> = Set((
        "app apps admin api apis async await auth backend frontend base64 bool cfg changelog checkout cli codebase "
        + "config configs const css csv ctx cpu database db dev dns docker dropdown dst email emoji endpoint enum env err "
        + "func gcp gif github gitlab golang graphql grpc gui guid html http http2 http3 https id ids ide iframe iam ime "
        + "imac impl init int int8 int16 int32 int64 io ios ip ipad iphone ipv4 ipv6 javascript jpeg jpg json jwt k8s "
        + "kubernetes linux localhost login logout mac macos md5 metadata middleware mp3 mp4 msg namespace navbar npm "
        + "oauth oauth2 ok online os payload pdf pinyin pip plugin plugins png popup pr prod protobuf ptr qa ram readme "
        + "refactor regex repo req res rime runtime s3 sdk sha1 sha256 sha512 sidebar sql src ssd ssh ssl stderr stdin "
        + "stdout str struct svg swift tcp timestamp tls tmp todo toml toolchain tooltip ts typescript udp ui uint uint8 "
        + "uint16 uint32 uint64 unicode uri url usb username utf8 utf16 utf32 util utils ux uuid v1 v2 v3 v4 v5 v6 v7 v8 "
        + "v9 var viewport webhook webview website wifi win32 win64 winrt workspace x64 x86 xcode xml yaml yarn amd64 "
        + "arm64 aarch64 ascii float32 float64 hotfix ec2 aws js ajax rest allinoneime bluetooth iso posix intel claude gemini gpt openai anthropic llama "
        + "mistral qwen deepseek haiku sonnet opus bedrock "
        + "usr lib bin sbin etc opt var com org net www macosx darwin linux gnu musl msvc"
    ).split(separator: " ").map(String.init))
}
