format = "UDZO"
filesystem = "HFS+"
compression_level = 9

files = [(defines["app"], "OpenShelf.app")]
symlinks = {"Applications": "/Applications"}
background = defines["background"]

window_rect = ((200, 200), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 14
icon_locations = {
    "OpenShelf.app": (165, 215),
    "Applications": (495, 215),
}
