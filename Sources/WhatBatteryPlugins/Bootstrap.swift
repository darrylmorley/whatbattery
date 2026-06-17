import WhatBatteryAppKit

/// Public-mirror stub. The private build's `WhatBatteryPlugins` registers the Pro
/// features (licence, history, analyzer, iDevice, export, notifications); the
/// open-source build ships this no-op so it links cleanly with nothing Pro
/// registered. The app gates Pro UI on the registry, which stays empty here.
public func bootstrapPlugins(registry: PluginRegistry) {
}
