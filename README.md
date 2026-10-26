# Mensa Uni Bern

DankMaterialShell plugin showing daily Mensa food menu from the University of Bern.

Data source: [Food2050.ch](https://app.food2050.ch/) weekly menu page — refreshed hourly. Shows dish name, description and vegetarian/vegan flag (no prices).

## Bar pill

Shows a restaurant icon. Hover it for a tooltip listing today's dishes for both Mensas (the selected one first).

Click the pill to open a popout showing both Mensas side by side (the primary one on the left), with the date at the top and, for each Mensa:

- Mensa name (click it to open the full weekly menu on Food2050)
- Today's dishes by category (Garden, Farm, …) with photo, description and a vegetarian/vegan flag. Click a dish name or photo to open its Food2050 page in the browser
- Error/loading status

On weekends the next day with a menu is shown.

## Installation

Clone directly into the plugins folder:

```bash
git clone https://github.com/paulhaider/dms-mensa ~/.config/DankMaterialShell/plugins/mensaUniBe
dms restart
```

Or, if you already have a local checkout, symlink it:

```bash
ln -s ~/dev/dms-mensa-unibe ~/.config/DankMaterialShell/plugins/mensaUniBe
dms restart
```

Then: Settings → Plugins → Scan for Plugins → enable **Mensa Uni Bern** → add to DankBar layout.

## Configuration

Both Mensas are always loaded. In the plugin settings, **Primary Mensa** (Gesellschaftsstrasse or Von Roll) chooses which one is shown first.

Photos can be turned off with **Show dish photos**. They are loaded from each dish's Food2050 page (one request per dish). The photo URLs are cached on disk, so each dish page is requested only once, and the photos stay loaded while the shell runs so reopening the popout does not download them again.

Pizza categories are hidden by default. To change that (for both Mensas), edit the comma-separated names under **Hidden categories**, e.g. `pizza` hides Daily Pizza, Weekly Pizza and Pizza Dello Chef. Matching is case-insensitive and on part of the name. Clear the field to show everything.

## Requirements

- DankMaterialShell >= 1.4.0
- Network access to `app.food2050.ch`

## Notes

Food2050 has no public API, so the plugin reads the dish data that the weekly menu page embeds as JSON. This depends on the page's internal structure, so if Food2050 changes it, the popout shows "Food2050 page format may have changed" until the parser is updated.

## License

[MIT](LICENSE)
