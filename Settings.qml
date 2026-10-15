import qs.Modules.Plugins

PluginSettings {
    pluginId: "mensaUniBe"

    SelectionSetting {
        settingKey: "mensaId"
        label: "Primary Mensa"
        description: "Shown first in the popout and tooltip"
        options: [
            { label: "Gesellschaftsstrasse", value: "1" },
            { label: "Von Roll", value: "3" }
        ]
        defaultValue: "1"
    }

    StringSetting {
        settingKey: "excludeCategories"
        label: "Hidden categories"
        description: "Comma-separated category names to hide, e.g. \"pizza, special\". Matches part of the name, ignoring case."
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "showImages"
        label: "Show dish photos"
        description: "Load a photo for each of today's dishes from its Food2050 page."
        defaultValue: true
    }
}
