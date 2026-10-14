import qs.Modules.Plugins

PluginSettings {
    pluginId: "mensaUniBe"

    StringSetting {
        settingKey: "mensaId"
        label: "Mensa Location"
        description: "Select location: 1 = Gesellschaftsstrasse, 3 = Von Roll"
        defaultValue: "1"
    }

    StringSetting {
        settingKey: "excludeCategories"
        label: "Hidden categories"
        description: "Comma-separated category names to hide, e.g. \"pizza, special\". Matches part of the name, ignoring case."
        defaultValue: ""
    }
}
