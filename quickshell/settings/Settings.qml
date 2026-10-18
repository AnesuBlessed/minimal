import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

FloatingWindow {
    id: root

    property bool showing: false
    property bool cardVisible: false
    property int selectedIndex: 0
    property string systemHost: "Linux"
    property string systemUptime: ""
    property var sink: Pipewire.defaultAudioSink
    property var navEntries: [{
        "group": "HARDWARE",
        "name": "Display",
        "short": "1",
        "icon": "\uf108",
        "page": "Display"
    }, {
        "group": "HARDWARE",
        "name": "Sound",
        "short": "2",
        "icon": "\uf028",
        "page": "Sound"
    }, {
        "group": "CONNECTIVITY",
        "name": "Network",
        "short": "3",
        "icon": "\uf1eb",
        "page": "Network"
    }, {
        "group": "CONNECTIVITY",
        "name": "Bluetooth",
        "short": "4",
        "icon": "󰂯",
        "page": "Bluetooth"
    }, {
        "group": "SYSTEM",
        "name": "Power & Sleep",
        "short": "5",
        "icon": "󰐥",
        "page": "Power"
    }, {
        "group": "SYSTEM",
        "name": "Maintenance",
        "short": "6",
        "icon": "󰋊",
        "page": "Storage"
    }]

    function show() {
        if (showing)
            return ;

        cardVisible = true;
        showing = true;
    }

    function hide() {
        if (!showing)
            return ;

        showing = false;
        Qt.quit();
    }

    function toggle() {
        showing ? hide() : show();
    }

    title: "Minimal Settings"
    color: "transparent"
    visible: showing
    implicitWidth: Math.min(820, (screen ? screen.width : 1366) - 32)
    implicitHeight: Math.min(560, (screen ? screen.height : 768) - 80)
    minimumSize: Qt.size(620, 400)
    onClosed: Qt.quit()

    Shortcut { sequence: "Escape"; onActivated: root.hide() }
    Shortcut { sequence: "Alt+1"; onActivated: root.selectedIndex = 0 }
    Shortcut { sequence: "Alt+2"; onActivated: root.selectedIndex = 1 }
    Shortcut { sequence: "Alt+3"; onActivated: root.selectedIndex = 2 }
    Shortcut { sequence: "Alt+4"; onActivated: root.selectedIndex = 3 }
    Shortcut { sequence: "Alt+5"; onActivated: root.selectedIndex = 4 }
    Shortcut { sequence: "Alt+6"; onActivated: root.selectedIndex = 5 }
    IpcHandler {
        target: "settings"
        function toggle() { root.toggle(); }
        function show() { root.show(); }
        function hide() { root.hide(); }
        function display() { root.selectedIndex = 0; root.show(); }
        function sound() { root.selectedIndex = 1; root.show(); }
        function network() { root.selectedIndex = 2; root.show(); }
        function bluetooth() { root.selectedIndex = 3; root.show(); }
        function power() { root.selectedIndex = 4; root.show(); }
        function storage() { root.selectedIndex = 5; root.show(); }
    }
    Rectangle {
        anchors.fill: parent
        color: Theme.glass
        radius: Theme.radius
        border.width: 1
        border.color: Theme.border

        Column {
            id: navigation
            x: 16; y: 20
            width: 164
            spacing: 4
            Text {
                text: "Minimal"
                height: 44
                leftPadding: 12
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitle
                font.weight: Font.DemiBold
            }
            Repeater {
                model: root.navEntries
                delegate: Button {
                    required property var modelData
                    required property int index
                    width: navigation.width
                    height: 40
                    text: modelData.name
                    Accessible.name: modelData.name
                    onClicked: root.selectedIndex = index
                    background: Rectangle {
                        radius: Theme.radiusSm
                        color: root.selectedIndex === index ? Theme.bgActive : (parent.hovered ? Theme.bgHover : "transparent")
                        border.width: parent.visualFocus ? 1 : 0
                        border.color: Theme.accent
                    }
                    contentItem: Row {
                        spacing: 10
                        leftPadding: 12
                        Text {
                            text: modelData.icon
                            color: root.selectedIndex === index ? Theme.accent : Theme.textDim
                            font.family: Theme.iconFont
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: modelData.name
                            color: root.selectedIndex === index ? Theme.text : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
        Text {
            x: 28
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            text: "Alt + 1–6 to switch"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSecondary
        }
        Rectangle {
            x: 196; y: 20
            width: 1; height: parent.height - 40
            color: Theme.border
        }
        Item {
            x: 217; y: 20
            width: parent.width - x - 20
            height: parent.height - 40
            Text {
                text: root.navEntries[root.selectedIndex].name
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 20
                font.weight: Font.DemiBold
                anchors.top: parent.top
                anchors.topMargin: 6
            }
            Button {
                anchors.right: parent.right
                width: 32; height: 32
                text: "×"
                Accessible.name: "Close settings"
                onClicked: root.hide()
                background: Rectangle {
                    radius: Theme.radiusSm
                    color: parent.hovered ? Theme.bgHover : "transparent"
                    border.width: parent.visualFocus ? 1 : 0
                    border.color: Theme.accent
                }
                contentItem: Text {
                    text: parent.text
                    color: Theme.textDim
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Loader {
                id: pageLoader
                anchors.fill: parent
                anchors.topMargin: 56
                clip: true
                active: root.showing
                source: "Tabs/" + root.navEntries[root.selectedIndex].page + ".qml"
            }
        }
    }
}
