import Foundation
import SteadyCore

/// Build-time switches. `HideUnreviewedContent` (Info.plist) is NO while the owner is the only tester:
/// unreviewed programs then show with a "Draft" badge. Set it to YES before any wider release and
/// the app shows only content a qualified person has marked reviewed.
enum AppConfig {
    static var hideUnreviewedContent: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "HideUnreviewedContent") as? Bool) ?? false
    }
    static var showDraft: Bool { !hideUnreviewedContent }
}
