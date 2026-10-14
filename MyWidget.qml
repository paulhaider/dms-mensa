import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string mensaId: pluginData.mensaId ?? "1"
    onMensaIdChanged: fetchMensaData()

    property var menus: ({})

    // Comma-separated category names (substring, case-insensitive) to hide, e.g. "pizza, garden"
    readonly property var excluded: String(pluginData.excludeCategories ?? "").split(",")
        .map(function(x) { return x.trim().toLowerCase() }).filter(function(x) { return x !== "" })

    // Date of the selected Mensa, shown once at the top of the popout
    readonly property string headerDate: {
        var d = (menus[mensaId] ?? {}).date
        return d && d !== "--" ? d : ""
    }

    // menus with excluded categories filtered out; used for display
    readonly property var shown: {
        var out = {}
        Object.keys(menus).forEach(function(id) {
            out[id] = Object.assign({}, menus[id], {
                dishes: menus[id].dishes.filter(function(d) {
                    var cat = d.category.toLowerCase()
                    return !excluded.some(function(x) { return cat.indexOf(x) >= 0 })
                })
            })
        })
        return out
    }

    readonly property var mensas: ({
        "1": { name: "Mensa Gesellschaftsstrasse", path: "universitat-bern,gesellschaftsstrasse/mensa-gesellschaftsstrasse" },
        "3": { name: "Mensa Von Roll", path: "universitat-bern,hochschulzentrum-vonroll/mensa-vonroll" }
    })

    // Selected mensa first, then the others
    readonly property var mensaOrder: [mensaId].concat(Object.keys(mensas).filter(function(id) { return id !== mensaId }))
    readonly property var current: menus[mensaId] ?? ({})

    function setMenu(id, patch) {
        var m = Object.assign({}, root.menus)
        m[id] = Object.assign({ name: root.mensas[id] ? root.mensas[id].name : "Mensa " + id, date: "--", dishes: [], loading: false, error: false, errorMessage: "" }, m[id], patch)
        root.menus = m
    }

    function fetchMensaData() {
        root.mensaOrder.forEach(function(id) { root.fetchMensa(id) })
    }

    function fetchMensa(id) {
        var mensa = root.mensas[id]
        if (!mensa) {
            root.setMenu(id, { dishes: [], error: true, errorMessage: "Invalid mensa ID" })
            return
        }
        root.setMenu(id, { loading: true, error: false, errorMessage: "" })

        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://app.food2050.ch/de/v2/zfv/" + mensa.path + "/mittagsverpflegung/menu/weekly")
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                root.setMenu(id, { loading: false, error: true, errorMessage: xhr.status ? "HTTP " + xhr.status : "Network error" })
                return
            }
            try {
                root.setMenu(id, Object.assign({ loading: false }, root.pickDay(root.parseMenu(xhr.responseText))))
            } catch (e) {
                root.setMenu(id, { loading: false, error: true, errorMessage: "Food2050 page format may have changed (" + e.message + ")" })
            }
        }
        xhr.send()
    }

    // The page embeds its data as escaped JSON; each dish is an OutletMenuItemDish object.
    function parseMenu(html) {
        var s = html.replace(/\\"/g, '"')
        var chunks = s.split('"__typename":"OutletMenuItemDish"').slice(1)
        var items = []
        for (var i = 0; i < chunks.length; i++) {
            var c = chunks[i]
            var d = c.match(/"detailUrl":"[^"]*?\/(\d{4}-\d\d-\d\d)"/)
            var n = c.match(/"name":"([^"]*)","description":"((?:[^"\\]|\\.)*)"/)
            if (!d || !n)
                continue
            // category is sometimes a back-reference ("$7:...") instead of an object
            var k = c.match(/"category":\{[^}]*"name":"([^"]*)"/)
            var veg = c.match(/"isVegetarian":(true|false)/)
            var vegan = c.match(/"isVegan":(true|false)/)
            items.push({
                date: d[1],
                category: k ? k[1] : "",
                name: n[1],
                description: n[2].replace(/\\u([0-9a-fA-F]{4})/g, function(m, h) { return String.fromCharCode(parseInt(h, 16)) }),
                vegetarian: !!veg && veg[1] === "true",
                vegan: !!vegan && vegan[1] === "true"
            })
        }
        // Fill missing categories from the same position on other days
        var seen = {}, byPos = {}
        items.forEach(function(it) {
            var pos = seen[it.date] = (seen[it.date] ?? -1) + 1
            it.pos = pos
            if (it.category && !byPos[pos]) byPos[pos] = it.category
        })
        items.forEach(function(it) { if (!it.category) it.category = byPos[it.pos] ?? "" })
        return items
    }

    function pickDay(items) {
        var now = new Date()
        var today = now.getFullYear() + "-" + ("0" + (now.getMonth() + 1)).slice(-2) + "-" + ("0" + now.getDate()).slice(-2)
        var days = []
        items.forEach(function(it) { if (days.indexOf(it.date) < 0) days.push(it.date) })
        days.sort()
        // Today if present, else next available day (weekend), else last day of the week.
        var day = days.filter(function(x) { return x >= today })[0] || days[days.length - 1]
        if (!day)
            return { dishes: [], date: "--", error: true, errorMessage: "No dishes found. Food2050 may have changed its page format, or no menu is published yet." }
        var p = day.split("-")
        return {
            dishes: items.filter(function(it) { return it.date === day }),
            date: new Date(p[0], p[1] - 1, p[2]).toLocaleDateString('de-CH', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }),
            error: false,
            errorMessage: ""
        }
    }

    Timer {
        interval: 3600000 // 1 hour
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchMensaData()
    }

    readonly property string tooltipText: {
        var parts = []
        mensaOrder.forEach(function(id) {
            var m = shown[id]
            if (!m)
                return
            var lines = [m.name]
            if (m.loading && m.dishes.length === 0)
                lines.push("Loading...")
            else if (m.error)
                lines.push("Error: " + m.errorMessage)
            else
                m.dishes.forEach(function(d) { lines.push("• " + d.name) })
            parts.push(lines.join("\n"))
        })
        return parts.join("\n\n")
    }

    // Real layout height, reported by the popout once it has been shown
    property real measuredHeight: 0
    // Until then, estimate from the data
    readonly property real estimatedHeight: {
        var h = 2 * Theme.spacingM
        mensaOrder.forEach(function(id) {
            var m = shown[id]
            if (!m)
                return
            h += 90
            m.dishes.forEach(function(d) { h += 70 + 18 * Math.ceil(d.description.length / 55) })
            if (m.error || m.loading)
                h += 30
        })
        return h
    }
    readonly property real popoutContentHeight: measuredHeight > 0 ? measuredHeight : estimatedHeight
    popoutHeight: Math.min(800, popoutContentHeight)

    popoutContent: Component {
        Flickable {
            id: flick
            clip: true
            implicitWidth: 500
            implicitHeight: Math.min(800, contentHeight)
            contentWidth: width
            contentHeight: body.height
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: root.measuredHeight = contentHeight

        Column {
            id: body
            spacing: Theme.spacingS
            padding: Theme.spacingM
            width: flick.width

            StyledText {
                text: root.headerDate
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                visible: text !== ""
            }

            Repeater {
                model: root.mensaOrder

                Column {
                    id: mensaCol
                    property var menu: root.shown[modelData] ?? ({})
                    spacing: Theme.spacingS
                    width: body.width - 2 * body.padding

                    StyledText {
                        text: mensaCol.menu.name ?? ""
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    // only when it differs from the date shown at the top
                    StyledText {
                        text: mensaCol.menu.date !== root.headerDate ? (mensaCol.menu.date ?? "") : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        visible: text !== "" && text !== "--"
                    }

                    Repeater {
                        model: mensaCol.menu.dishes ?? []

                        Column {
                            spacing: Theme.spacingXS
                            width: parent.width

                            StyledText {
                                text: modelData.category + (modelData.vegan ? " · vegan" : (modelData.vegetarian ? " · vegetarisch" : ""))
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.primary
                                font.weight: Font.Bold
                                visible: text !== ""
                            }

                            StyledText {
                                text: modelData.name
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                wrapMode: Text.WordWrap
                                width: parent.width
                            }

                            StyledText {
                                text: modelData.description
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                width: parent.width
                            }
                        }
                    }

                    StyledText {
                        text: mensaCol.menu.loading ? "Loading..." : (mensaCol.menu.error ? "Error: " + mensaCol.menu.errorMessage : "")
                        font.pixelSize: Theme.fontSizeSmall
                        color: mensaCol.menu.error ? "#e57c34" : Theme.surfaceVariantText
                        visible: text !== ""
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Item {
                        width: 1
                        height: Theme.spacingM
                    }
                }
            }
        }
        }
    }

    horizontalBarPill: Component {
        DankIcon {
            name: "restaurant"
            size: root.iconSize
            anchors.verticalCenter: parent.verticalCenter

            HoverHandler { id: hover }
            ToolTip {
                visible: hover.hovered && root.tooltipText !== ""
                delay: 300
                text: root.tooltipText
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "restaurant"
            size: root.iconSize
            anchors.horizontalCenter: parent.horizontalCenter

            HoverHandler { id: hover }
            ToolTip {
                visible: hover.hovered && root.tooltipText !== ""
                delay: 300
                text: root.tooltipText
            }
        }
    }
}
