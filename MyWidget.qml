import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string mensaId: pluginData.mensaId ?? "1"

    property var menus: ({})
    readonly property bool showImages: pluginData.showImages ?? true

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
                var day = root.pickDay(root.parseMenu(xhr.responseText))
                root.setMenu(id, Object.assign({ loading: false }, day))
                root.fetchImages(day.dishes)
            } catch (e) {
                root.setMenu(id, { loading: false, error: true, errorMessage: "Food2050 page format may have changed (" + e.message + ")" })
            }
        }
        xhr.send()
    }

    // Photo URLs of the dishes being shown
    readonly property var photoUrls: {
        var urls = []
        if (!showImages)
            return urls
        mensaOrder.forEach(function(id) {
            ((shown[id] ?? {}).dishes ?? []).forEach(function(d) {
                var u = photoUrl(images[d.url])
                if (u && urls.indexOf(u) < 0)
                    urls.push(u)
            })
        })
        return urls
    }

    // Keeps the photos loaded while the shell runs. The popout is destroyed on close, but Qt's
    // pixmap cache serves identical url + sourceSize to its Images without downloading again.
    Repeater {
        model: root.photoUrls

        Image {
            source: modelData
            sourceSize: Qt.size(root.photoWidth, root.photoHeight)
            asynchronous: true
            cache: true
            visible: false
        }
    }

    readonly property int photoWidth: 600
    readonly property int photoHeight: 280

    // Scraped data is untrusted: only allow known HTTPS hosts for links and photos
    function foodUrl(u) { return /^https:\/\/app\.food2050\.ch\//.test(u ?? "") ? u : "" }
    function photoUrl(u) { return /^https:\/\/storage\.googleapis\.com\//.test(u ?? "") ? u : "" }
    function plain(t) { return String(t).replace(/[<>]/g, "") }

    function openDish(u) {
        var url = root.foodUrl(u)
        if (url)
            Qt.openUrlExternally(url)
    }

    // dish detail URL -> photo URL ("" = none); filled lazily for the dishes being shown
    property var images: root.loadImageCache()

    // Persisted across restarts (PluginService state file); entries older than 14 days are dropped
    function loadImageCache() {
        var cached = PluginService.loadPluginState("mensaUniBe", "imageCache", {})
        var cutoff = new Date(Date.now() - 14 * 86400000).toISOString().slice(0, 10)
        var out = {}
        Object.keys(cached).forEach(function(url) {
            if (root.foodUrl(url) && url.slice(-10) >= cutoff)
                out[url] = root.photoUrl(cached[url])
        })
        return out
    }

    function fetchImages(dishes) {
        if (!root.showImages)
            return
        dishes.forEach(function(dish) {
            if (!dish.url || root.images[dish.url] !== undefined)
                return
            var xhr = new XMLHttpRequest()
            xhr.open("GET", dish.url)
            xhr.timeout = 15000
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return
                var m = xhr.status === 200 ? xhr.responseText.replace(/\\"/g, '"').match(/"imageUrl":"([^"]+)"/) : null
                // leave unset on network errors so the next refresh retries
                if (xhr.status !== 200)
                    return
                var imgs = Object.assign({}, root.images)
                imgs[dish.url] = m ? root.photoUrl(m[1]) : ""
                root.images = imgs
                PluginService.savePluginState("mensaUniBe", "imageCache", imgs)
            }
            xhr.send()
        })
    }

    // The page embeds its data as escaped JSON; each dish is an OutletMenuItemDish object.
    function parseMenu(html) {
        // Quotes inside dish names arrive triple-escaped (\\\"); protect them before unescaping the rest
        var s = html.replace(/\\\\\\"/g, "\u0001").replace(/\\"/g, '"')
        var chunks = s.split('"__typename":"OutletMenuItemDish"').slice(1)
        var items = []
        for (var i = 0; i < chunks.length; i++) {
            var c = chunks[i]
            var d = c.match(/"detailUrl":"([^"]*?\/(\d{4}-\d\d-\d\d))"/)
            var n = c.match(/"name":"([^"]*)","description":"((?:[^"\\]|\\.)*)"/)
            if (!d || !n)
                continue
            // The category is sometimes a back-reference ("$7:...") instead of an object;
            // the URL slug (...,hauptspeisen,daily-pizza/<date>) is always there.
            var k = c.match(/"category":\{[^}]*"name":"([^"]*)"/)
            var slug = d[1].match(/,([a-z0-9-]+)\/\d{4}-\d\d-\d\d$/)
            var category = k ? k[1] : (slug ? slug[1].split("-").map(function(w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ") : "")
            var veg = c.match(/"isVegetarian":(true|false)/)
            var vegan = c.match(/"isVegan":(true|false)/)
            items.push({
                date: d[2],
                url: root.foodUrl(d[1]),
                category: root.plain(category),
                name: root.plain(n[1].replace(/\u0001/g, '"')),
                description: root.plain(n[2].replace(/\u0001/g, '"').replace(/\\u([0-9a-fA-F]{4})/g, function(m, h) { return String.fromCharCode(parseInt(h, 16)) })),
                vegetarian: !!veg && veg[1] === "true",
                vegan: !!vegan && vegan[1] === "true"
            })
        }
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
        // Mensas are side by side, so the tallest one counts
        var tallest = 0
        mensaOrder.forEach(function(id) {
            var m = shown[id]
            if (!m)
                return
            var h = 60
            m.dishes.forEach(function(d) { h += 70 + 18 * Math.ceil(d.description.length / 35) + (showImages && images[d.url] ? 150 : 0) })
            if (m.error || m.loading)
                h += 30
            tallest = Math.max(tallest, h)
        })
        return 2 * Theme.spacingM + 40 + tallest
    }
    readonly property real popoutContentHeight: measuredHeight > 0 ? measuredHeight : estimatedHeight
    popoutWidth: 900
    popoutHeight: Math.min(800, popoutContentHeight)

    popoutContent: Component {
        Flickable {
            id: flick
            clip: true
            implicitWidth: 900
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

            Row {
                id: mensaRow
                spacing: Theme.spacingL
                width: body.width - 2 * body.padding

            Repeater {
                model: root.mensaOrder

                Column {
                    id: mensaCol
                    property var menu: root.shown[modelData] ?? ({})
                    spacing: Theme.spacingS
                    width: (mensaRow.width - (root.mensaOrder.length - 1) * mensaRow.spacing) / root.mensaOrder.length

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
                                textFormat: Text.PlainText
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.primary
                                font.weight: Font.Bold
                                visible: text !== ""
                            }

                            Image {
                                source: root.showImages ? root.photoUrl(root.images[modelData.url]) : ""
                                width: parent.width
                                height: 140
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(root.photoWidth, root.photoHeight)
                                asynchronous: true
                                cache: true
                                visible: source != "" && status !== Image.Error

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openDish(modelData.url)
                                }
                            }

                            StyledText {
                                text: modelData.name
                                textFormat: Text.PlainText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                wrapMode: Text.WordWrap
                                width: parent.width

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openDish(modelData.url)
                                }
                            }

                            StyledText {
                                text: modelData.description
                                textFormat: Text.PlainText
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
