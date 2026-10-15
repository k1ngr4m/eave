import Foundation

// lolPing catalog at 6d67ee1. Art is © Riot Games; see Support/DesktopPing/LICENSE.
struct DesktopEmote: Identifiable {
    let id: String
    let name: String
    var localizedName: String { NSLocalizedString(name, comment: "") }
    static let catalog: [Self] = [
        .init(id: "facepalm", name: "Facepalm"),
        .init(id: "unworthy", name: "Unworthy"),
        .init(id: "unworthy_cn", name: "Unworthy (Chinese text)"),
        .init(id: "poro_snax", name: "Poro Snax"),
        .init(id: "sad_kitten", name: "Sad Kitten"),
        .init(id: "cheeky_poro", name: "Cheeky Poro"),
        .init(id: "angry_kitty", name: "Angry Kitty"),
        .init(id: "gg_heart", name: "GG <3"),
        .init(id: "bee_happy", name: "Bee Happy"),
        .init(id: "bee_mad", name: "Bee Mad"),
        .init(id: "bee_sad", name: "Bee Sad"),
        .init(id: "snoozy_poro", name: "Snoozy Poro"),
        .init(id: "wahaha", name: "Wahaha"),
        .init(id: "omg_love_it", name: "OMG I love it"),
        .init(id: "poro_ride", name: "Poro Ride"),
        .init(id: "dont_make_me_laugh", name: "Don't Make Me Laugh"),
        .init(id: "woah_dizzy", name: "Woah…Dizzy"),
        .init(id: "haha_hilarious", name: "Haha HILARIOUS"),
        .init(id: "gasp", name: "Gasp!"),
        .init(id: "super_approved", name: "Super-Approved"),
        .init(id: "pain", name: "PaiN…"),
        .init(id: "laughing_out_loud", name: "Laughing Out LOUD"),
        .init(id: "hats_off", name: "Hat's Off"),
        .init(id: "call_me", name: "Call Me!"),
        .init(id: "think_about_it", name: "Think About It"),
        .init(id: "unimpressed", name: "Animated Unimpressed!"),
        .init(id: "did_you_just", name: "Animated Did You Just?"),
        .init(id: "nice_try", name: "Nice Try"),
        .init(id: "nice", name: "Nice"),
        .init(id: "despair", name: "Despair"),
        .init(id: "does_not_compute", name: "Does Not Compute"),
        .init(id: "come_at_me", name: "Come at Me"),
        .init(id: "how_could_you", name: "How Could You"),
        .init(id: "scout_approved", name: "Scout-Approved"),
        .init(id: "maybe_next_time", name: "Maybe Next Time"),
        .init(id: "okay", name: "Okay"),
        .init(id: "good_job_buddy", name: "Good Job, Buddy!"),
        .init(id: "teamwork", name: "Teamwork!"),
        .init(id: "i_will_destroy_you", name: "I will destroy you"),
        .init(id: "not_today", name: "Not Today!"),
        .init(id: "oh", name: "Oh..."),
        .init(id: "come_again", name: "Come again?"),
        .init(id: "magpie_oopsie", name: "Magpie Oopsie"),
        .init(id: "such_foolishness", name: "Such Foolishness"),
    ]
    static let ids = Set(catalog.map(\.id))
    static let defaultWheel = ["unworthy_cn", "poro_snax", "sad_kitten", "cheeky_poro", "angry_kitty", "gg_heart", "bee_happy", "bee_mad"]
}
