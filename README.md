# Spell Timer Plugin for Outlander

This plugin provides variables for spells from the `percWindow`.

```
> /spelltimer
SpellTimer Plugin v1
Active:
  EaseBurden (26 roisaen)
Inactive:
  ManifestForce (0 roisaen)
```

```
> #echo Active: $SpellTimer.EaseBurden.active Duration: $SpellTimer.EaseBurden.duration
Active: 1 Duration: 26
```

# Installation

* Download the latest `SpellTimerPlugin.bundle.zip` file from the [Releases](https://github.com/outlander-app/plugin-spell-timer/releases). Unzip and copy the `.bundle` file into your `~/Documents/Outlander/Plugins` folder.
* Download [allspells.txt](https://github.com/outlander-app/plugin-package/blob/main/allspells.txt) and copy it to the `Plugins` folder.
* Restart Outlander and the plugin should load.
