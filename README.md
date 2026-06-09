# DateWidget

A tiny macOS desktop widget for people who want the date, clocks, weather, and a little ambient nonsense sitting directly on the desktop.

> This is a vibecode result from Alerix, Claude, and Codex. It is not a polished product, a framework, or a carefully maintained showcase of software architecture. It is a thing that exists, looks nice, and may occasionally remind you that computers are held together with monster energy drink and enough praying.

## What It Does

- Shows the current day, month, weekday, and multiple configurable clocks.
- Displays current weather and a short forecast using Open-Meteo, because I don’t want to pay Apple.
- Fetches refreshable quotes from theytoldme.com.
- Can swap the quote area for a small live audio equalizer.
- Lives as a borderless desktop overlay across Spaces.
- Supports right-click controls for refreshing quotes, moving the widget, snapping to corners, opening settings, and quitting.
- Saves widget position and settings in `UserDefaults`.

## Requirements

- macOS 26 Tahoe or later. (Liquid Glass)
- Xcode 26 or later.
- Network access for weather, city lookup, and quote refreshes.
- Audio capture permissions may be needed if you use the equalizer.

The UI uses Liquid Glass APIs, so older macOS/Xcode versions are expected to be unhappy.

## Running

Open `DateWidget.xcodeproj` in Xcode and press **Run**.

There is no package manager setup, no CI, and no ceremony. It is a straightforward Xcode project.

## Controls

Right-click the widget to open the context menu:

- **Refresh Quote** fetches a new quote.
- **Move Widget** toggles drag/edit mode.
- **Position** snaps the widget to a screen corner.
- **Settings...** opens clock, weather, appearance, and launch-at-login options.
- **Quit** exits the app.

The right side of the widget can be clicked or swiped between calendar and forecast views.

## Settings

The settings window lets you:

- Enable, disable, label, and choose time zones for clocks.
- Look up a weather city and switch between Celsius and Fahrenheit.
- Choose between quote and equalizer content for the left panel.
- Toggle a contrast backing for busy wallpapers.
- Enable launch at login.

## Data Sources

- Weather and geocoding: [Open-Meteo](https://open-meteo.com/)
- Quotes: [theytoldme.com](https://theytoldme.com/)

## Known Issues

- The equalizer depends on the system audio tap implementation and platform permissions. So if it doesn’t work, grant the permission in System Settings.
- The widget is built for a specific modern macOS look and size rather than every desktop arrangement in existence. Fork and adapt it for your setup.

## License

MIT. See [LICENSE](LICENSE).
