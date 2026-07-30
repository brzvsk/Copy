# dmgbuild settings for Copy's DMG. dmgbuild writes the window layout + background
# straight into the volume's .DS_Store (no Finder/AppleScript automation), so the
# branded background and icon positions render reliably even on headless CI runners
# (unlike create-dmg). Invoked by Scripts/release.sh, which substitutes the two
# placeholders below before running dmgbuild.
application = "APP_PATH_PLACEHOLDER"
appname = "Copy.app"

# Compressed, read-only image (same format as the previous hdiutil UDZO output).
format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}

# App icon on the left, Applications folder on the right, at the same height; the
# background art's drag arrow points from one to the other.
icon_locations = {appname: (165, 250), "Applications": (495, 250)}
background = "BACKGROUND_PLACEHOLDER"

window_rect = ((200, 120), (660, 470))
default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
text_size = 12
icon_size = 120
hide_extension = [appname]
