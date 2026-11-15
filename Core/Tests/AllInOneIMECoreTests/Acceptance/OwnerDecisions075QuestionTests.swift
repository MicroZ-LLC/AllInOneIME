import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner decisions 2026-11-14 (0.7.5), part 2: one @'s "is it a question" test (`OneAt.isQuestion`). Written from the
/// spec by a separate agent; the implementer doesn't edit it (AGENTS.md rule 11).
///
/// A table of cases, every one of which holds: a question word used as a real question makes a question (什么 in 这是什么,
/// 几 in 几点开会, an English first word with an apostrophe: what's, isn't); the same words used indefinitely don't (没什么,
/// 过几天, 哪怕, 多少有点累, 哪里哪里, "what a lovely day"); a text with both is a question (没什么事吗); a text ending in "?" or
/// "？" always is. Every case true or false before 0.7.5 keeps its answer.
struct OwnerDecisions075QuestionTests {
    /// Questions, as before 0.7.5.
    static let questionsBefore = [
        "红烧肉怎么做", "你吃饭了吗", "how do I undo a commit", "pizza or pasta?", "Is it done", "多少钱",
    ]

    /// Questions the spec adds or names: English first words with an apostrophe (straight or curly) and the other
    /// auxiliaries, Chinese question words used as questions.
    static let questionsNamed = [
        "what's the capital of Peru", "how's it going", "who's coming tonight", "where’s the station",
        "Did you see my email", "was it fun", "were they there", "will it rain tomorrow", "would you mind",
        "whose bag is this", "isn't it ready", "don't you like it",
        "几点开会", "你要几个", "星期几", "这是什么", "哪个好", "你在哪里", "为什么不行", "怎么了", "你呢", "一共多少",
    ]

    /// Any text ending in "?" or "？" is a question, whatever its words (even one that is no question without the mark).
    static let questionMarks = [
        "ok?", "好？", "really?", "thank you for the gift?", "过几天再说？", "what a lovely day?", "没什么?", "明天下午3点开会？",
    ]

    /// Both an indefinite use and a real question word: a question.
    static let both = ["没什么事吗"]

    /// Not questions, as before 0.7.5.
    static let statementsBefore = ["这家店的菜很好吃", "thank you for the gift", "show me how", "明天下午3点开会"]

    /// Not questions the spec names: the question words used indefinitely, and an English exclamation.
    static let statementsNamed = [
        "过几天再说", "我几乎忘了", "没什么", "哪怕下雨也去", "没什么大不了的", "我什么都不想吃", "什么也没说", "怎么都行",
        "他不怎么喝酒", "好几个人来了", "这几天很忙", "十几个", "多少有点累", "或多或少", "哪里哪里", "what a lovely day",
    ]

    @Test func questionsAsBeforeStayQuestions() {
        for text in Self.questionsBefore {
            #expect(OneAt.isQuestion(text), "\(text)")
        }
    }

    @Test func questionWordsUsedAsQuestionsAreQuestions() {
        for text in Self.questionsNamed {
            #expect(OneAt.isQuestion(text), "\(text)")
        }
    }

    @Test func aQuestionMarkAtTheEndIsAlwaysAQuestion() {
        for text in Self.questionMarks {
            #expect(OneAt.isQuestion(text), "\(text)")
        }
    }

    @Test func anIndefiniteWordWithARealQuestionWordIsAQuestion() {
        for text in Self.both {
            #expect(OneAt.isQuestion(text), "\(text)")
        }
    }

    @Test func statementsAsBeforeStayStatements() {
        for text in Self.statementsBefore {
            #expect(!OneAt.isQuestion(text), "\(text)")
        }
    }

    @Test func questionWordsUsedIndefinitelyAreNoQuestion() {
        for text in Self.statementsNamed {
            #expect(!OneAt.isQuestion(text), "\(text)")
        }
    }
}
