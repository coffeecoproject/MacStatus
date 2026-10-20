def rows_with_panels(count):
    return [
        {"AXRole": "AXApplication", "AXFrontmost": True},
        {
            "AXRole": "AXMenuBarItem",
            "AXDescription": "CPU 使用率",
            "AXTitle": " CPU 50%",
            "AXValue": "CPU 使用率 50%"
        }
    ] + [{"AXRole": "AXPopover"} for _ in range(count)]
