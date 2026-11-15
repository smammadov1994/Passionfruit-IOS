import Foundation
@testable import Tempo

/// JSON exactly as SPEC section 3 describes it.
enum Fixtures {
    static let partner: String = """
    {"id":"u_maya","firstName":"Maya","age":29,"city":"Brooklyn","distanceKm":2.4,"photoUrl":"https://cdn.example.com/p/maya.jpg","intention":"long_term"}
    """

    static let message: String = """
    {"id":"m_1","matchId":"mt_1","senderId":"u_maya","text":"Hello you","sentAt":"2026-11-14T21:04:05.123Z","clientId":"c-1"}
    """

    static let match: String = """
    {"id":"mt_1","partner":\(partner),"matchedAt":"2026-11-14T21:00:00.000Z","lastMessage":\(message),"unreadCount":2}
    """

    static let preferences: String = """
    {"ageMin":25,"ageMax":38,"maxDistanceKm":40,"intentions":["long_term","marriage"],"children":["wants","open"],"religions":["agnostic"],"minEducation":"bachelors","smokingOk":["never"],"drinkingOk":["never","socially"],"notifyOnlineSingles":true}
    """

    static let user: String = """
    {"id":"u_me","firstName":"Alex","birthdate":"1996-05-14","gender":"man","interestedIn":["woman","nonbinary"],"bio":"Hi","city":"New York","lat":40.75,"lng":-73.98,"photoUrls":["https://cdn.example.com/p/a.jpg"],"intention":"long_term","children":"open","religion":"agnostic","education":"masters","smoking":"never","drinking":"socially","isPremium":true,"premiumExpiresAt":"2026-12-14T00:00:00.000Z","onboardingComplete":true,"strikes":1,"suspendedUntil":null,"preferences":\(preferences)}
    """

    static let freshUser: String = """
    {"id":"u_new","firstName":"","birthdate":null,"gender":null,"interestedIn":[],"bio":"","city":"","photoUrls":[],"isPremium":false,"onboardingComplete":false,"strikes":0,"preferences":{"ageMin":18,"ageMax":99,"maxDistanceKm":100,"notifyOnlineSingles":false}}
    """

    static let config: String = """
    {"dateDurationSec":240,"turnDurationSec":30,"decisionWindowSec":20,"freeDailyDates":5,"frameSampleIntervalSec":3,"iceServers":[{"urls":["stun:stun.example.com:3478"]},{"urls":["turn:turn.example.com:3478"],"username":"u","credential":"c"}]}
    """

    static let usageFree: String = """
    {"datesToday":3,"limit":5,"resetsAt":"2026-11-15T05:00:00.000Z"}
    """

    static let usagePremium: String = """
    {"datesToday":9,"limit":null,"resetsAt":"2026-11-15T05:00:00.000Z"}
    """

    static let errorEnvelope: String = """
    {"error":{"code":"limit_reached","message":"You have used your free dates for today."}}
    """

    // Server → Client frames

    static let queueStatus: String = """
    {"type":"queue.status","compatibleOnline":23,"position":2}
    """

    static let queueLimit: String = """
    {"type":"queue.limit","limit":5,"resetsAt":"2026-11-15T05:00:00.000Z"}
    """

    static let dateMatched: String = """
    {"type":"date.matched","dateId":"d_1","partner":\(partner),"role":"caller","iceServers":[{"urls":["stun:stun.example.com:3478"]},{"urls":["turn:turn.example.com:3478"],"username":"u","credential":"c"}]}
    """

    static let dateStarted: String = """
    {"type":"date.started","dateId":"d_1","startsAt":"2026-11-14T21:00:00.000Z","endsAt":"2026-11-14T21:04:00.000Z"}
    """

    static let rtcOffer: String = """
    {"type":"rtc.signal","dateId":"d_1","payload":{"kind":"offer","sdp":"v=0\\r\\no=- 1 2 IN IP4 127.0.0.1"}}
    """

    static let rtcIce: String = """
    {"type":"rtc.signal","dateId":"call:mt_1","payload":{"kind":"ice","candidate":"candidate:1 1 UDP 2122252543 192.168.1.2 54321 typ host","sdpMid":"0","sdpMLineIndex":0}}
    """

    static let icebreakerTurn: String = """
    {"type":"icebreaker.turn","dateId":"d_1","question":"What would your perfect Sunday look like?","questionIndex":3,"speakerId":"u_maya","turnEndsAt":"2026-11-14T21:01:30.500Z","turnDurationSec":30}
    """

    static let dateEndedTimer: String = """
    {"type":"date.ended","dateId":"d_1","reason":"timer","decisionDeadline":"2026-11-14T21:04:20.000Z"}
    """

    static let dateEndedPartnerLeft: String = """
    {"type":"date.ended","dateId":"d_1","reason":"partner_left"}
    """

    static let dateResultMatch: String = """
    {"type":"date.result","dateId":"d_1","outcome":"match","match":\(match)}
    """

    static let dateResultNoMatch: String = """
    {"type":"date.result","dateId":"d_1","outcome":"no_match"}
    """

    static let moderationWarn: String = """
    {"type":"moderation.action","dateId":"d_1","action":"warn","category":"sexual_language","message":"Keep it respectful."}
    """

    static let moderationEnd: String = """
    {"type":"moderation.action","dateId":"d_1","action":"end","category":"nudity","message":"This date was ended."}
    """

    static let chatMessage: String = """
    {"type":"chat.message","message":\(message)}
    """

    static let matchRemoved: String = """
    {"type":"match.removed","matchId":"mt_1"}
    """

    static let callInvite: String = """
    {"type":"call.invite","matchId":"mt_1","fromUserId":"u_maya"}
    """

    static let callAccept: String = """
    {"type":"call.accept","matchId":"mt_1","fromUserId":"u_maya"}
    """

    static let callDecline: String = """
    {"type":"call.decline","matchId":"mt_1","fromUserId":"u_maya"}
    """

    static let callEnd: String = """
    {"type":"call.end","matchId":"mt_1","fromUserId":"u_maya"}
    """

    static let accountSuspended: String = """
    {"type":"account.suspended","until":"2026-11-21T00:00:00.000Z","reason":"Three strikes."}
    """

    static let accountSuspendedOpenEnded: String = """
    {"type":"account.suspended","reason":"Pending review."}
    """

    static let serverError: String = """
    {"type":"error","code":"not_in_date","message":"You are not in that date."}
    """

    static let pong: String = """
    {"type":"pong"}
    """

    static let unknownFrame: String = """
    {"type":"something.new","value":1}
    """

    // Swift values used by the store tests

    static let maya = Partner(id: "u_maya", firstName: "Maya", age: 29, city: "Brooklyn", distanceKm: 2, photoUrl: nil, intention: .longTerm)

    static func date(_ iso: String) -> Date {
        TempoJSON.parseDate(iso) ?? Date(timeIntervalSince1970: 0)
    }

    static func data(_ json: String) -> Data {
        json.data(using: .utf8) ?? Data()
    }
}
