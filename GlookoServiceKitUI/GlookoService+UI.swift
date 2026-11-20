import SwiftUI
import LoopKit
import LoopKitUI
import GlookoServiceKit

extension GlookoService: @retroactive ServiceUI {

    public static var image: UIImage? { nil }

    public static func setupViewController(colorPalette: LoopUIColorPalette,
                                           pluginHost: PluginHost,
                                           allowDebugFeatures: Bool) -> SetupUIResult<ServiceViewController, ServiceUI> {
        let nav = ServiceNavigationController()
        nav.isNavigationBarHidden = true

        Task {
            let service = GlookoService(hostIdentifier: pluginHost.hostIdentifier, hostVersion: pluginHost.hostVersion)

            let view = await GlookoSettingsView(service: service, onCreated: {
                service.completeCreate()
                Task { await nav.notifyServiceCreatedAndOnboarded(service) }
            }, dismiss: {
                Task { await nav.notifyComplete() }
            })
            let hostingController = await UIHostingController(rootView: view)
            await nav.pushViewController(hostingController, animated: false)
        }

        return .userInteractionRequired(nav)
    }

    public func settingsViewController(colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> ServiceViewController {
        let nav = ServiceNavigationController()
        nav.isNavigationBarHidden = true

        Task {
            let view = await GlookoSettingsView(service: self, onCreated: {}, dismiss: {
                Task { await nav.notifyComplete() }
            })
            let hostingController = await UIHostingController(rootView: view)
            await nav.pushViewController(hostingController, animated: false)
        }

        return nav
    }
}
