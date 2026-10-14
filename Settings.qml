import qs.Modules.Plugins

PluginSettings {
    pluginId: "mensaUniBe"

    StringSetting {
        settingKey: "mensaId"
        label: "Mensa Location"
        description: "Select location: 1 = Gesellschaftsstrasse, 3 = Von Roll"
        defaultValue: "1"
    }
}
