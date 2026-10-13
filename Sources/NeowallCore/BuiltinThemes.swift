/// Palettes taken from the Omarchy theme `colors.toml` files
/// (https://github.com/basecamp/omarchy/tree/master/themes), reduced to the
/// keys neowall reads, with the `neowall_inks` key added.
enum BuiltinThemes {
    static let sources: [String: String] = [
        "catppuccin": """
        neowall_inks = ["accent", "magenta", "cyan"]
        background = "#1e1e2e"
        foreground = "#cdd6f4"
        muted = "#585b70"
        dark_foreground = "#6c7086"
        accent = "#89b4fa"
        magenta = "#f5c2e7"
        cyan = "#94e2d5"
        """,
        "catppuccin-latte": """
        neowall_inks = ["accent", "magenta", "cyan"]
        background = "#eff1f5"
        foreground = "#4c4f69"
        muted = "#acb0be"
        dark_foreground = "#9ca0b0"
        accent = "#1e66f5"
        magenta = "#ea76cb"
        cyan = "#179299"
        """,
        "ethereal": """
        neowall_inks = ["accent", "foreground", "magenta"]
        background = "#060b1e"
        foreground = "#ffcead"
        muted = "#6d7db6"
        dark_foreground = "#6d7db6"
        accent = "#7d82d9"
        magenta = "#c89dc1"
        """,
        "everforest": """
        neowall_inks = ["green", "accent", "yellow"]
        background = "#2d353b"
        foreground = "#d3c6aa"
        muted = "#475258"
        dark_foreground = "#4f585e"
        green = "#a7c080"
        accent = "#7fbbb3"
        yellow = "#dbbc7f"
        """,
        "flexoki-light": """
        neowall_inks = ["accent", "cyan", "orange"]
        background = "#fffcf0"
        foreground = "#100f0f"
        muted = "#b7b5ac"
        dark_foreground = "#878580"
        accent = "#205ea6"
        cyan = "#3aa99f"
        orange = "#d0772b"
        """,
        "gruvbox": """
        neowall_inks = ["yellow", "accent", "orange"]
        background = "#282828"
        foreground = "#d4be98"
        muted = "#665c54"
        dark_foreground = "#7c6f64"
        yellow = "#d8a657"
        accent = "#7daea3"
        orange = "#e1875c"
        """,
        "hackerman": """
        neowall_inks = ["accent", "cyan", "blue"]
        background = "#0b0c16"
        foreground = "#ddf7ff"
        muted = "#2d3450"
        dark_foreground = "#6a6e95"
        accent = "#82fb9c"
        cyan = "#7cf8f7"
        blue = "#829dd4"
        """,
        "kanagawa": """
        neowall_inks = ["blue", "magenta", "yellow"]
        background = "#1f1f28"
        foreground = "#dcd7ba"
        muted = "#54546d"
        dark_foreground = "#727169"
        blue = "#7e9cd8"
        magenta = "#957fb8"
        yellow = "#c0a36e"
        """,
        "last-horizon": """
        neowall_inks = ["accent", "green", "magenta"]
        background = "#0c0b0c"
        foreground = "#fafcfb"
        muted = "#584e51"
        dark_foreground = "#584e51"
        accent = "#b59790"
        green = "#87a9b0"
        magenta = "#c4d8e2"
        """,
        "lumon": """
        neowall_inks = ["accent", "cyan", "blue"]
        background = "#16242d"
        foreground = "#d6e2ee"
        muted = "#304860"
        dark_foreground = "#4d86b0"
        accent = "#8bc9eb"
        cyan = "#b4e4f6"
        blue = "#6fb8e3"
        """,
        "lupine": """
        neowall_inks = ["accent", "magenta", "red"]
        background = "#fafafa"
        foreground = "#212121"
        muted = "#9e9e9e"
        dark_foreground = "#757575"
        accent = "#3264eb"
        magenta = "#8a4ad7"
        red = "#c900c4"
        """,
        "matte-black": """
        neowall_inks = ["accent", "foreground", "red"]
        background = "#121212"
        foreground = "#bebebe"
        muted = "#333333"
        dark_foreground = "#555555"
        accent = "#e68e0d"
        red = "#d35f5f"
        """,
        "miasma": """
        neowall_inks = ["accent", "cyan", "magenta"]
        background = "#222222"
        foreground = "#c2c2b0"
        muted = "#666666"
        dark_foreground = "#555555"
        accent = "#78824b"
        cyan = "#c9a554"
        magenta = "#bb7744"
        """,
        "nord": """
        neowall_inks = ["accent", "cyan", "magenta"]
        background = "#2e3440"
        foreground = "#d8dee9"
        muted = "#4c566a"
        dark_foreground = "#667080"
        accent = "#81a1c1"
        cyan = "#88c0d0"
        magenta = "#b48ead"
        """,
        "osaka-jade": """
        neowall_inks = ["accent", "cyan", "foreground"]
        background = "#111c18"
        foreground = "#c1c497"
        muted = "#53685b"
        dark_foreground = "#81b8a8"
        accent = "#509475"
        cyan = "#2dd5b7"
        """,
        "retro-82": """
        neowall_inks = ["accent", "cyan", "red"]
        background = "#05182e"
        foreground = "#f6dcac"
        muted = "#2a6b78"
        dark_foreground = "#3f8f8a"
        accent = "#faa968"
        cyan = "#8cbfb8"
        red = "#f85525"
        """,
        "ristretto": """
        neowall_inks = ["accent", "yellow", "magenta"]
        background = "#2c2525"
        foreground = "#e6d9db"
        muted = "#72696a"
        dark_foreground = "#72696a"
        accent = "#f38d70"
        yellow = "#f9cc6c"
        magenta = "#a8a9eb"
        """,
        "rose-pine": """
        neowall_inks = ["accent", "magenta", "cyan"]
        background = "#faf4ed"
        foreground = "#575279"
        muted = "#cecacd"
        dark_foreground = "#9893a5"
        accent = "#56949f"
        magenta = "#907aa9"
        cyan = "#d7827e"
        """,
        "solitude": """
        neowall_inks = ["accent", "green", "yellow"]
        background = "#101315"
        foreground = "#cacccc"
        muted = "#4b4e55"
        dark_foreground = "#4b4e55"
        accent = "#798186"
        green = "#9fa5a9"
        yellow = "#d9dbdc"
        """,
        "tokyo-night": """
        neowall_inks = ["accent", "magenta", "bright_cyan"]
        background = "#1a1b26"
        foreground = "#a9b1d6"
        muted = "#414868"
        dark_foreground = "#565f89"
        accent = "#7aa2f7"
        magenta = "#ad8ee6"
        bright_cyan = "#0db9d7"
        """,
        "vantablack": """
        neowall_inks = ["accent", "foreground", "cyan"]
        background = "#000000"
        foreground = "#ffffff"
        muted = "#7a7a7a"
        dark_foreground = "#505050"
        accent = "#8d8d8d"
        cyan = "#b0b0b0"
        """,
        "white": """
        neowall_inks = ["accent", "foreground", "blue"]
        background = "#ffffff"
        foreground = "#000000"
        muted = "#808080"
        dark_foreground = "#c0c0c0"
        accent = "#6e6e6e"
        blue = "#1a1a1a"
        """,
    ]
}
