import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.aayushstha03.meeting-notes"
  ipcTarget: moduleName

  property var recentNotes: []
  property var meetings: []
  property string currentMeetingId: ""
  property string currentMeetingName: "Meeting notes"
  property string statusMessage: ""
  property bool statusIsError: false
  property bool saving: false
  property bool managingSessions: false
  property bool sessionBusy: false
  property string pendingDeleteId: ""
  property date now: new Date()

  readonly property string helperPath: Qt.resolvedUrl("meeting-notes").toString().replace(/^file:\/\//, "")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    if (authorField.text === "" && !authorProc.running) authorProc.running = true
  }

  function defaultMeetingName() {
    return "new-meeting " + Qt.formatDate(new Date(), "dd/MM/yy")
  }

  // Shift+Tab reaches us as Key_Backtab on some layouts and as Tab with the
  // shift modifier on others. Treat both as "walk the cycle backwards".
  function isBackTab(event) {
    return (event.modifiers & Qt.ShiftModifier) !== 0 || event.key === Qt.Key_Backtab
  }

  function createMeeting() {
    var name = meetingNameField.text.trim()
    if (name === "") name = defaultMeetingName()
    if (sessionBusy) return
    sessionBusy = true
    statusMessage = ""
    sessionProc.action = "create"
    sessionProc.command = [helperPath, "create", name]
    sessionProc.running = true
  }

  function renameMeeting() {
    var name = meetingNameField.text.trim()
    if (currentMeetingId === "" || name === "") {
      statusMessage = "Enter a new name for this meeting"
      statusIsError = true
      meetingNameField.forceActiveFocus()
      return
    }
    if (sessionBusy) return
    sessionBusy = true
    statusMessage = ""
    sessionProc.action = "rename"
    sessionProc.command = [helperPath, "rename", currentMeetingId, name]
    sessionProc.running = true
  }

  function selectMeeting(meetingId) {
    if (sessionBusy || meetingId === currentMeetingId) return
    clearDeleteConfirmation()
    sessionBusy = true
    statusMessage = ""
    sessionProc.action = "select"
    sessionProc.command = [helperPath, "select", meetingId]
    sessionProc.running = true
  }

  function clearDeleteConfirmation() {
    pendingDeleteId = ""
    deleteConfirmTimer.stop()
    if (statusMessage.indexOf("Press trash again") === 0) statusMessage = ""
  }

  function requestDelete(meetingId, meetingName) {
    if (sessionBusy || meetings.length <= 1) return
    if (pendingDeleteId !== meetingId) {
      pendingDeleteId = meetingId
      statusMessage = "Press trash again to delete “" + meetingName + "”"
      statusIsError = false
      deleteConfirmTimer.restart()
      return
    }
    sessionBusy = true
    deleteConfirmTimer.stop()
    statusMessage = ""
    sessionProc.action = "delete"
    sessionProc.command = [helperPath, "delete", meetingId]
    sessionProc.running = true
  }

  function saveNote() {
    var author = authorField.text.trim()
    var note = noteField.text.trim()
    if (author === "" || note === "") {
      statusMessage = "Add both an author and a note"
      statusIsError = true
      if (author === "") authorField.forceActiveFocus()
      else noteField.forceActiveFocus()
      return
    }
    if (saving) return
    saving = true
    statusMessage = ""
    addProc.command = [helperPath, "add", author, note]
    addProc.running = true
  }

  function parseState(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      recentNotes = Array.isArray(parsed.recent_notes) ? parsed.recent_notes : []
      meetings = Array.isArray(parsed.meetings) ? parsed.meetings : []
      currentMeetingId = parsed.current ? String(parsed.current.id || "") : ""
      currentMeetingName = parsed.current ? String(parsed.current.name || "Meeting notes") : "Meeting notes"
    } catch (error) {
      recentNotes = []
      meetings = []
      statusMessage = "Could not read meetings"
      statusIsError = true
    }
  }

  onOpenedChanged: if (opened) {
    managingSessions = false
    clearDeleteConfirmation()
    now = new Date()
    refresh()
    Qt.callLater(function() { authorField.forceActiveFocus() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.now = new Date()
  }

  Timer {
    id: deleteConfirmTimer
    interval: 5000
    onTriggered: root.clearDeleteConfirmation()
  }

  Process {
    id: stateProc
    command: [root.helperPath, "state", "7"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseState(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") {
        root.statusMessage = String(text).trim()
        root.statusIsError = true
      }
    }
  }

  Process {
    id: authorProc
    command: [root.helperPath, "author"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var saved = String(text || "").trim()
        if (root.opened && authorField.text === "" && saved !== "") {
          authorField.text = saved
          authorField.forceActiveFocus()
        }
      }
    }
  }

  Process {
    id: addProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: addError
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.saving = false
      if (exitCode === 0) {
        noteField.text = ""
        root.statusMessage = "Saved at " + Qt.formatTime(new Date(), "h:mm AP")
        root.statusIsError = false
        root.refresh()
        noteField.forceActiveFocus()
      } else {
        root.statusMessage = String(addError.text || "Could not save the note").trim()
        root.statusIsError = true
      }
    }
  }

  Process {
    id: sessionProc
    property string action: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: sessionError
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.sessionBusy = false
      if (exitCode === 0) {
        var completedAction = action
        root.statusMessage = completedAction === "create" ? "New meeting started"
          : completedAction === "rename" ? "Meeting renamed"
          : completedAction === "delete" ? "Session deleted · recovery copy saved"
          : "Meeting switched"
        root.statusIsError = false
        root.pendingDeleteId = ""
        root.refresh()
        if (completedAction === "create" || completedAction === "select") {
          meetingNameField.text = ""
          root.managingSessions = false
          if (completedAction === "create") authorField.text = ""
          authorField.forceActiveFocus()
        }
      } else {
        root.statusMessage = String(sessionError.text || "Could not update the meeting").trim()
        root.statusIsError = true
      }
    }
  }

  Process {
    id: openProc
    command: [root.helperPath, "open"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: openError
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.statusMessage = "Opened meeting log"
        root.statusIsError = false
      } else {
        root.statusMessage = String(openError.text || "Could not open the meeting log").trim()
        root.statusIsError = true
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "✎"
    tooltipText: "Meeting notes"
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (!openProc.running) openProc.running = true
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: authorField
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // PanelKeyCatcher takes keys before its children, so every item that
      // runs its own Tab/Enter handling has to be listed here.
      blocked: authorField.activeFocus || noteField.activeFocus || meetingNameField.activeFocus
        || saveButton.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(titleBlock.implicitHeight, timeText.implicitHeight)

          Column {
            id: titleBlock
            anchors.left: parent.left
            anchors.right: timeText.left
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(2)

            Text {
              text: root.currentMeetingName
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              text: "MEETING NOTES"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: Style.space(1)
            }
          }

          Text {
            id: timeText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatTime(root.now, "h:mm AP")
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width - sessionsButton.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              text: root.meetings.length + (root.meetings.length === 1 ? " session" : " sessions")
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              id: sessionsButton
              text: root.managingSessions ? "Done" : "Manage sessions"
              iconText: root.managingSessions ? "✓" : "☰"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              onClicked: {
                root.managingSessions = !root.managingSessions
                if (root.managingSessions) {
                  meetingNameField.text = ""
                  meetingNameField.forceActiveFocus()
                } else {
                  root.clearDeleteConfirmation()
                  meetingNameField.text = ""
                  noteField.forceActiveFocus()
                }
              }
            }
          }

          Column {
            visible: root.managingSessions
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: meetingNameField
              width: parent.width
              placeholderText: root.defaultMeetingName()
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.managingSessions = false; event.accepted = true
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                  meetingNameField.forceActiveFocus(); event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.renameMeeting(); event.accepted = true
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "New meeting"
                iconText: "+"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                bordered: true
                enabled: !root.sessionBusy
                onClicked: root.createMeeting()
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Rename current"
                iconText: "✎"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                bordered: true
                enabled: !root.sessionBusy
                onClicked: root.renameMeeting()
              }
            }

            PanelSectionHeader {
              text: "SWITCH SESSION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.meetings

              Row {
                id: sessionRow
                required property var modelData
                width: parent.width
                spacing: Style.space(6)

                Button {
                  width: parent.width - deleteButton.width - parent.spacing
                  text: (String(sessionRow.modelData.id || "") === root.currentMeetingId ? "✓  " : "")
                    + String(sessionRow.modelData.name || "Untitled") + "  ·  " + Number(sessionRow.modelData.note_count || 0)
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  bordered: String(sessionRow.modelData.id || "") === root.currentMeetingId
                  leftAlign: true
                  enabled: !root.sessionBusy
                  onClicked: root.selectMeeting(String(sessionRow.modelData.id || ""))
                }

                Button {
                  id: deleteButton
                  iconText: "󰆴"
                  tooltipText: root.meetings.length <= 1 ? "At least one session must remain"
                    : root.pendingDeleteId === String(sessionRow.modelData.id || "") ? "Click again to delete"
                    : "Delete session"
                  foreground: root.pendingDeleteId === String(sessionRow.modelData.id || "")
                    ? (root.bar ? root.bar.urgent : Color.urgent) : root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  horizontalPadding: Style.space(9)
                  bordered: root.pendingDeleteId === String(sessionRow.modelData.id || "")
                  enabled: !root.sessionBusy && root.meetings.length > 1
                  onClicked: root.requestDelete(String(sessionRow.modelData.id || ""), String(sessionRow.modelData.name || "Untitled"))
                }
              }
            }

            Text {
              visible: root.statusMessage !== ""
              width: parent.width
              text: root.statusMessage
              color: root.statusIsError ? (root.bar ? root.bar.urgent : Color.urgent) : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }
        }

        PanelSeparator { visible: !root.managingSessions; foreground: root.foreground }

        Column {
          visible: !root.managingSessions
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "NEW POINT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: authorField
            width: parent.width
            placeholderText: "Author — e.g. Person A"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.close(); event.accepted = true
              } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                (root.isBackTab(event) ? saveButton : noteField).forceActiveFocus(); event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                noteField.forceActiveFocus(); event.accepted = true
              }
            }
          }

          TextField {
            id: noteField
            width: parent.width
            placeholderText: "What did they say?"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.close(); event.accepted = true
              } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                (root.isBackTab(event) ? authorField : saveButton).forceActiveFocus(); event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.saveNote(); event.accepted = true
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              id: saveButton
              width: parent.width - openButton.width - parent.spacing
              text: root.saving ? "Saving…" : "Save note"
              iconText: root.saving ? "󰦖" : "✓"
              iconSpinning: root.saving
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              focusable: true
              enabled: !root.saving
              onClicked: root.saveNote()
              // Return, Enter, and Space fall through to Button's own
              // handlers, which emit clicked().
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.close(); event.accepted = true
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                  (root.isBackTab(event) ? noteField : authorField).forceActiveFocus(); event.accepted = true
                }
              }
            }

            Button {
              id: openButton
              text: "Open meeting"
              iconText: "↗"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              enabled: !openProc.running
              onClicked: if (!openProc.running) openProc.running = true
            }
          }

          Text {
            visible: root.statusMessage !== ""
            width: parent.width
            text: root.statusMessage
            color: root.statusIsError ? (root.bar ? root.bar.urgent : Color.urgent) : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Column {
          visible: !root.managingSessions && root.recentNotes.length > 0
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "RECENT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.recentNotes

            Item {
              required property var modelData
              width: parent.width
              implicitHeight: Math.max(noteTime.implicitHeight, noteBody.implicitHeight)

              Text {
                id: noteTime
                anchors.left: parent.left
                anchors.top: parent.top
                width: Style.space(68)
                text: String(modelData.time || "")
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                id: noteBody
                anchors.left: noteTime.right
                anchors.right: parent.right
                anchors.top: parent.top
                text: "<b>" + String(modelData.author || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") + ":</b> "
                  + String(modelData.note || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                textFormat: Text.RichText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }
    }
  }
}
