import SwiftUI

struct VideoWorkflowView: View {
  var onNavigate: (AppScreen) -> Void

  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var authService: AuthService

  @State private var project: VideoProject? = nil
  @State private var activeCaptureRequest: CaptureRequest? = nil
  @State private var reviewTake: VideoCaptureTake? = nil
  @State private var floorplanRoomCount: Int = 0
  @State private var roomOptions: [RoomFloorSelection] = []
  @State private var selectedCaptureKind: VideoCaptureKind = .walkthrough
  @State private var selectedRoomOptionId: String = "\(RoomTaxonomy.defaultRoomId)|\(FloorTaxonomy.defaultFloorId)"
  @State private var isEditTakePresented = false
  @State private var editTakeId: UUID? = nil
  @State private var editCaptureKind: VideoCaptureKind = .walkthrough
  @State private var editRoomOptionId: String = "\(RoomTaxonomy.defaultRoomId)|\(FloorTaxonomy.defaultFloorId)"
  @State private var editFinalRole: VideoCaptureFinalRole = .detail
  @State private var editPriorityScore: Int = 3
  @State private var editSequenceIndex: Int = 1
  @State private var editNote: String = ""
  @State private var manifestAlertText: String = ""
  @State private var activeAlert: WorkflowAlert? = nil
  @State private var isJobPickerPresented = false

  private var projectKey: String? {
    let trimmed = settings.selectedJobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private var hasProjectContext: Bool {
    projectKey != nil
  }

  private var manualRoomOptions: [RoomFloorSelection] {
    [
      RoomFloorSelection(roomId: "exterior", floorId: FloorTaxonomy.defaultFloorId),
      RoomFloorSelection(roomId: RoomTaxonomy.defaultRoomId, floorId: FloorTaxonomy.defaultFloorId),
      RoomFloorSelection(roomId: "unknown", floorId: FloorTaxonomy.defaultFloorId)
    ]
  }

  private var availableRoomOptions: [RoomFloorSelection] {
    roomOptions.isEmpty ? manualRoomOptions : roomOptions
  }

  private var selectedRoomOption: RoomFloorSelection {
    availableRoomOptions.first(where: { $0.id == selectedRoomOptionId })
      ?? availableRoomOptions.first
      ?? RoomFloorSelection(roomId: RoomTaxonomy.defaultRoomId, floorId: FloorTaxonomy.defaultFloorId)
  }

  private var hasFloorplan: Bool {
    floorplanRoomCount > 0
  }

  private var capturesSorted: [VideoCaptureTake] {
    (project?.captures ?? []).sorted { $0.createdAt > $1.createdAt }
  }

  private var finalTimelineSorted: [VideoCaptureTake] {
    (project?.captures ?? [])
      .filter { $0.finalRole != .excluded }
      .sorted { lhs, rhs in
        if lhs.sequenceIndex != rhs.sequenceIndex { return lhs.sequenceIndex < rhs.sequenceIndex }
        if lhs.priorityScore != rhs.priorityScore { return lhs.priorityScore > rhs.priorityScore }
        return lhs.createdAt < rhs.createdAt
      }
  }

  private var roomCaptureGroups: [RoomCaptureGroup] {
    let grouped = Dictionary(grouping: project?.captures ?? []) { take in
      roomOptionKey(roomId: take.roomId, floorId: take.floorId)
    }
    let groups = grouped.values.map { takes -> RoomCaptureGroup in
      let first = takes.first
      return RoomCaptureGroup(
        roomId: first?.roomId ?? RoomTaxonomy.defaultRoomId,
        floorId: first?.floorId ?? FloorTaxonomy.defaultFloorId,
        takes: takes.sorted { $0.createdAt < $1.createdAt }
      )
    }
    return groups.sorted { lhs, rhs in lhs.label < rhs.label }
  }

  var body: some View {
    ZStack {
      Color(.systemGray6).ignoresSafeArea()

      VStack(spacing: 14) {
        header

        ScrollView {
          VStack(spacing: 12) {
            if hasProjectContext {
              projectCard

              stepCard(
                icon: "square.grid.2x2",
                title: l10n("video.workflow.step.floorplan.optional.title"),
                subtitle: floorplanSubtitle
              ) {
                onNavigate(.floorplan)
              }

              captureSetupCard

              stepCard(
                icon: "video",
                title: l10n("video.workflow.step.capture.title"),
                subtitle: captureStepSubtitle
              ) {
                ensureProject()
                let option = selectedRoomOption
                activeCaptureRequest = CaptureRequest(
                  takeId: UUID(),
                  kind: selectedCaptureKind,
                  roomId: option.roomId,
                  floorId: option.floorId
                )
              }

              capturesCard
              finalSelectionCard

              stepCard(
                icon: "waveform",
                title: l10n("video.workflow.step.acoustics.title"),
                subtitle: l10n("video.workflow.step.acoustics.subtitle")
              ) {
                // next iteration
              }

              stepCard(
                icon: "doc.badge.gearshape",
                title: l10n("video.workflow.step.package.title"),
                subtitle: manifestSubtitle()
              ) {
                generateManifest()
              }
            } else {
              missingJobCard
            }
          }
          .padding(.horizontal, 18)
          .padding(.bottom, 18)
        }

        BottomNavBar(selected: .start) { tab in
          switch tab {
          case .start: onNavigate(.start)
          case .help: onNavigate(.help)
          case .sunPlan: onNavigate(.sunPlan)
          case .camera: onNavigate(.camera)
          case .panorama: onNavigate(AppFeatureFlags.secondaryCaptureScreen)
          case .gallery: onNavigate(.gallery)
          case .manual: onNavigate(.settings)
          }
        }
      }
    }
    .sheet(isPresented: $isJobPickerPresented) {
      JobSelectionSheet(
        title: "Job fuer Video waehlen",
        subtitle: "Video-Projekte brauchen einen echten Job, damit Aufnahmen, Manifest und spaetere Zuordnung nicht im Demo-Kontext landen.",
        allowsClear: false,
        clearLabel: "",
        requiresSelection: true,
        onSelect: { job in
          applySelectedJob(job)
          ensureProject()
          refreshFloorplanStatus()
        },
        onClear: {}
      )
      .environmentObject(authService)
      .environmentObject(settings)
    }
    .fullScreenCover(item: $activeCaptureRequest) { request in
      if let project {
        MainVideoCaptureScreen(
          projectId: project.id,
          takeId: request.takeId,
          captureKind: request.kind,
          roomId: request.roomId,
          floorId: request.floorId,
          onCancel: { activeCaptureRequest = nil },
          onFinished: { take in
            addCapture(take)
            activeCaptureRequest = nil
          }
        )
      } else {
        VStack(spacing: 12) {
          Text(l10n("video.workflow.error.projectCreate"))
          Button(l10n("common.close")) { activeCaptureRequest = nil }
        }
      }
    }
    .fullScreenCover(item: $reviewTake) { take in
      if let url = resolveCaptureURL(relativePath: take.videoRelativePath) {
        MainVideoReviewScreen(
          videoURL: url,
          onDiscard: {
            deleteCapture(take.id)
            reviewTake = nil
          },
          onContinue: {
            reviewTake = nil
          }
        )
      } else {
        VStack(spacing: 12) {
          Text(l10n("video.workflow.error.videoMissing"))
          Button(l10n("common.close")) { reviewTake = nil }
        }
      }
    }
    .sheet(isPresented: $isEditTakePresented) {
      NavigationStack {
        Form {
          Section(l10n("video.workflow.edit.section.captureType")) {
            Picker(l10n("video.workflow.edit.field.type"), selection: $editCaptureKind) {
              ForEach(VideoCaptureKind.allCases) { kind in
                Text(kind.displayName).tag(kind)
              }
            }
            .pickerStyle(.segmented)
          }

          Section(l10n("video.workflow.edit.section.room")) {
            if roomOptions.isEmpty {
              Text(l10n("video.workflow.edit.noRooms"))
            }
            Picker(l10n("video.workflow.field.room"), selection: $editRoomOptionId) {
              ForEach(availableRoomOptions) { option in
                Text(option.label).tag(option.id)
              }
            }
            .pickerStyle(.menu)
          }

          Section(l10n("video.workflow.edit.section.finalUse")) {
            Picker(l10n("video.workflow.edit.field.usage"), selection: $editFinalRole) {
              ForEach(VideoCaptureFinalRole.allCases) { role in
                Text(role.displayName).tag(role)
              }
            }
            .pickerStyle(.menu)

            Stepper(value: $editPriorityScore, in: 1...5) {
              Text(String(format: l10n("video.workflow.edit.rating.format"), editPriorityScore))
            }

            Stepper(value: $editSequenceIndex, in: 1...999) {
              Text(String(format: l10n("video.workflow.edit.sequence.format"), editSequenceIndex))
            }

            TextField(l10n("video.workflow.edit.note.placeholder"), text: $editNote, axis: .vertical)
              .lineLimit(2...4)
              .submitLabel(.done)
              .onSubmit {
                hideSystemKeyboard()
              }
          }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(l10n("video.workflow.edit.title"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(l10n("common.cancel")) { isEditTakePresented = false }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(l10n("common.save")) {
              applyEdit()
              isEditTakePresented = false
            }
            .disabled(editTakeId == nil)
          }
        }
        .keyboardDoneToolbar()
      }
      .presentationDetents([.medium, .large])
    }
    .onAppear {
      project = nil
      ensureProject()
      refreshFloorplanStatus()
      presentJobPickerIfNeeded()
    }
    .onChange(of: settings.selectedJobId) { _, _ in
      project = nil
      ensureProject()
      refreshFloorplanStatus()
      presentJobPickerIfNeeded()
    }
    .alert(item: $activeAlert) { alert in
      switch alert {
      case .manifest:
        return Alert(
          title: Text(l10n("video.workflow.manifest.title")),
          message: Text(manifestAlertText),
          dismissButton: .cancel(Text(l10n("common.ok")))
        )
      case .manifestNeedsCapture:
        return Alert(
          title: Text(l10n("video.workflow.alert.noCaptures.title")),
          message: Text(l10n("video.workflow.alert.noCaptures.message")),
          dismissButton: .cancel(Text(l10n("common.ok")))
        )
      }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Button(action: { onNavigate(.camera) }) {
        Image(systemName: "chevron.left")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.7))
          .frame(width: 36, height: 36)
          .background(Color.white)
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel(l10n("common.back"))

      VStack(alignment: .leading, spacing: 2) {
        Text(l10n("video.workflow.header.title"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.85))
        Text(settings.jobLabel.isEmpty ? "Bitte zuerst Job waehlen" : settings.jobLabel)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.55))
          .lineLimit(1)
      }

      Spacer()

      Button {
        isJobPickerPresented = true
      } label: {
        Image(systemName: "briefcase")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.7))
          .frame(width: 36, height: 36)
          .background(Color.white)
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Job waehlen")
    }
    .padding(.horizontal, 18)
    .padding(.top, 16)
  }

  private var projectCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(l10n("video.workflow.project.title"))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.8))

      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(settings.jobLabel.isEmpty ? l10n("video.workflow.project.noJob") : settings.jobLabel)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.8))
          Text(projectInfoSubtitle)
            .font(.system(size: 12))
            .foregroundStyle(Color.black.opacity(0.6))
        }
        Spacer()
        if let project {
          Text(String(project.id.uuidString.prefix(8)))
            .foregroundStyle(Color.black.opacity(0.45))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
      }
    }
    .padding(14)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private var missingJobCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Job zuerst festlegen")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))

      Text("Der Video-Flow legt Projektdateien, Aufnahmen und Manifest pro Job ab. Ohne Job wuerden neue Daten im falschen Projekt landen.")
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.62))
        .fixedSize(horizontal: false, vertical: true)

      Button {
        isJobPickerPresented = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "briefcase")
            .font(.system(size: 15, weight: .semibold))
          Text("Job waehlen")
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(red: 0.29, green: 0.35, blue: 0.29))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
    }
    .padding(14)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private var captureSetupCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(l10n("video.workflow.setup.title"))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))

      HStack(spacing: 10) {
        HStack(spacing: 6) {
          Image(systemName: settings.videoStabilizationEnabled ? "camera.fill" : "gyroscope")
            .font(.system(size: 11, weight: .semibold))
          Text(settings.videoStabilizationEnabled
               ? l10n("video.workflow.setup.mode.handheld")
               : l10n("video.workflow.setup.mode.gimbal"))
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.black.opacity(0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.06))
        .clipShape(Capsule())

        Spacer()

        Button {
          settings.videoStabilizationEnabled.toggle()
        } label: {
          Text(settings.videoStabilizationEnabled
               ? l10n("video.workflow.setup.stabilization.on")
               : l10n("video.workflow.setup.stabilization.off"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.09))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }

      Text(settings.videoStabilizationEnabled
           ? l10n("video.workflow.setup.status.handheld")
           : l10n("video.workflow.setup.status.gimbal"))
        .font(.system(size: 11))
        .foregroundStyle(Color.black.opacity(0.58))
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        ForEach(VideoCaptureKind.allCases) { kind in
          Button {
            selectedCaptureKind = kind
          } label: {
            HStack(spacing: 6) {
              Image(systemName: kind.icon)
                .font(.system(size: 11, weight: .semibold))
              Text(kind.displayName)
                .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selectedCaptureKind == kind ? Color.black : Color.black.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selectedCaptureKind == kind ? Color.black.opacity(0.09) : Color.black.opacity(0.04))
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }

      if roomOptions.isEmpty {
        Text(l10n("video.workflow.setup.noFloorplanRooms"))
          .font(.system(size: 11))
          .foregroundStyle(Color.black.opacity(0.55))
          .fixedSize(horizontal: false, vertical: true)
      }

      Picker(l10n("video.workflow.field.room"), selection: $selectedRoomOptionId) {
        ForEach(availableRoomOptions) { option in
          Text(option.label).tag(option.id)
        }
      }
      .pickerStyle(.menu)
    }
    .padding(14)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private var capturesCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(l10n("video.workflow.captures.title"))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.82))
        Spacer()
        Text("\(capturesSorted.count)")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.5))
      }

      if capturesSorted.isEmpty {
        Text(l10n("video.workflow.captures.empty"))
          .font(.system(size: 12))
          .foregroundStyle(Color.black.opacity(0.6))
      } else {
        ForEach(capturesSorted) { take in
          captureRow(take)
        }
      }
    }
    .padding(14)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private var finalSelectionCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(l10n("video.workflow.finalSelection.title"))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.82))
        Spacer()
        Text(String(format: l10n("video.workflow.finalSelection.activeCount.format"), finalTimelineSorted.count))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.5))
      }

      if roomCaptureGroups.isEmpty {
        Text(l10n("video.workflow.finalSelection.empty"))
          .font(.system(size: 12))
          .foregroundStyle(Color.black.opacity(0.6))
      } else {
        ForEach(roomCaptureGroups) { group in
          VStack(alignment: .leading, spacing: 6) {
            Text(group.label)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.76))

            Picker(l10n("video.workflow.finalSelection.bestTake"), selection: primaryTakeBinding(for: group)) {
              ForEach(Array(group.takes.enumerated()), id: \.element.id) { idx, take in
                Text(String(format: l10n("video.workflow.finalSelection.takeOption.format"), idx + 1, take.kind.displayName, take.priorityScore))
                  .tag(take.id.uuidString)
              }
            }
            .pickerStyle(.menu)

            Text(l10n("video.workflow.finalSelection.hint"))
              .font(.system(size: 11))
              .foregroundStyle(Color.black.opacity(0.52))
          }
          .padding(.vertical, 4)
        }

        if !finalTimelineSorted.isEmpty {
          Divider()
          Text(l10n("video.workflow.finalSelection.activeOrder"))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.72))
          ForEach(finalTimelineSorted.prefix(8)) { take in
            Text(String(format: l10n("video.workflow.finalSelection.orderRow.format"),
                        take.sequenceIndex,
                        RoomTaxonomy.room(id: take.roomId).displayName,
                        take.kind.displayName))
              .font(.system(size: 11))
              .foregroundStyle(Color.black.opacity(0.62))
          }
        }
      }
    }
    .padding(14)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private func captureRow(_ take: VideoCaptureTake) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: take.kind.icon)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.65))
        .frame(width: 30, height: 30)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(String(format: l10n("video.workflow.captureRow.title.format"),
                    take.kind.displayName,
                    RoomTaxonomy.room(id: take.roomId).displayName))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.82))
        Text(String(format: l10n("video.workflow.captureRow.meta.format"),
                    FloorTaxonomy.floor(id: take.floorId).shortDisplayName,
                    captureDateText(take.createdAt)))
          .font(.system(size: 11))
          .foregroundStyle(Color.black.opacity(0.55))
        Text(String(format: l10n("video.workflow.captureRow.role.format"),
                    take.finalRole.displayName,
                    take.priorityScore,
                    take.sequenceIndex))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.56))
      }

      Spacer()

      VStack(spacing: 8) {
        Button {
          toggleCaptureIncluded(take.id)
        } label: {
          Image(systemName: take.finalRole == .excluded ? "circle" : "checkmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(take.finalRole == .excluded ? Color.black.opacity(0.45) : Color.green.opacity(0.9))
        }

        Button {
          moveCaptureInFinalOrder(take.id, delta: -1)
        } label: {
          Image(systemName: "chevron.up.circle")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.65))
        }
        .disabled(!canMoveCapture(take.id, delta: -1))
        .opacity(canMoveCapture(take.id, delta: -1) ? 1 : 0.35)

        Button {
          moveCaptureInFinalOrder(take.id, delta: 1)
        } label: {
          Image(systemName: "chevron.down.circle")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.65))
        }
        .disabled(!canMoveCapture(take.id, delta: 1))
        .opacity(canMoveCapture(take.id, delta: 1) ? 1 : 0.35)
      }
      .buttonStyle(.plain)

      VStack(spacing: 8) {
        Button {
          reviewTake = take
        } label: {
          Image(systemName: "play.circle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.75))
        }

        Button {
          beginEdit(take)
        } label: {
          Image(systemName: "pencil")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.65))
        }

        Button(role: .destructive) {
          deleteCapture(take.id)
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.red.opacity(0.85))
        }
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 6)
  }

  private var floorplanSubtitle: String {
    if hasFloorplan {
      return String(format: l10n("video.workflow.subtitle.floorplan.done.format"), floorplanRoomCount)
    }
    return l10n("video.workflow.subtitle.floorplan.todo")
  }

  private var captureStepSubtitle: String {
    guard hasFloorplan else {
      return l10n("video.workflow.subtitle.capture.independent")
    }
    return capturesSorted.isEmpty
      ? l10n("video.workflow.subtitle.capture.first")
      : String(format: l10n("video.workflow.subtitle.capture.more.format"), capturesSorted.count)
  }

  private var projectInfoSubtitle: String {
    let rooms = hasFloorplan
      ? String(format: l10n("video.workflow.projectInfo.rooms.format"), floorplanRoomCount)
      : l10n("video.workflow.projectInfo.rooms.none")
    return String(format: l10n("video.workflow.projectInfo.format"),
                  rooms,
                  capturesSorted.count,
                  finalTimelineSorted.count)
  }

  private func stepCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.55))
          .frame(width: 38, height: 38)
          .background(Color.white)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
          .frame(width: 44, height: 44)

        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.82))
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(Color.black.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.28))
      }
      .padding(14)
      .background(Color.white)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }
    .buttonStyle(.plain)
  }

  private func ensureProject() {
    guard let projectKey else {
      project = nil
      return
    }
    if project == nil {
      let projectId = loadOrCreateProjectId(for: projectKey)
      var loaded = VideoProject(
        id: projectId,
        jobId: settings.selectedJobId,
        jobLabel: settings.jobLabel,
        roomId: RoomTaxonomy.defaultRoomId,
        floorId: FloorTaxonomy.defaultFloorId
      )
      loaded.captures = (try? VideoProjectStore.loadCaptures(projectId: projectId)) ?? []
      migrateLegacyCaptureIfNeeded(&loaded)
      normalizeCaptureMetadata(&loaded)
      updateLegacyURLs(&loaded)
      project = loaded
    } else {
      project?.jobId = settings.selectedJobId
      project?.jobLabel = settings.jobLabel
    }
  }

  private func refreshFloorplanStatus() {
    guard let projectKey else {
      floorplanRoomCount = 0
      roomOptions = []
      selectedRoomOptionId = manualRoomOptions.first?.id ?? ""
      editRoomOptionId = manualRoomOptions.first?.id ?? ""
      return
    }

    do {
      let floorplan = try FloorplanProjectStore.loadOrCreate(projectKey: projectKey)
      floorplanRoomCount = floorplan.roomScans.count

      let sorted = floorplan.roomScans.sorted { $0.createdAt < $1.createdAt }
      var seen = Set<String>()
      var options: [RoomFloorSelection] = []
      for scan in sorted {
        let roomId = RoomTaxonomy.normalizedRoomId(scan.roomId)
        let floorId = FloorTaxonomy.normalizedFloorId(scan.floorId)
        let key = roomOptionKey(roomId: roomId, floorId: floorId)
        if seen.contains(key) { continue }
        seen.insert(key)
        options.append(RoomFloorSelection(roomId: roomId, floorId: floorId))
      }
      roomOptions = options

      let available = options.isEmpty ? manualRoomOptions : options
      if !available.contains(where: { $0.id == selectedRoomOptionId }) {
        selectedRoomOptionId = available.first?.id ?? ""
      }
      if !available.contains(where: { $0.id == editRoomOptionId }) {
        editRoomOptionId = available.first?.id ?? ""
      }
    } catch {
      floorplanRoomCount = 0
      roomOptions = []
      selectedRoomOptionId = manualRoomOptions.first?.id ?? ""
      editRoomOptionId = manualRoomOptions.first?.id ?? ""
    }
  }

  private func addCapture(_ take: VideoCaptureTake) {
    guard var project else { return }
    var updated = take
    updated.sequenceIndex = (project.captures.map(\.sequenceIndex).max() ?? 0) + 1
    updated.priorityScore = min(max(updated.priorityScore, 1), 5)

    let roomKey = roomOptionKey(roomId: updated.roomId, floorId: updated.floorId)
    let hasPrimaryInRoom = project.captures.contains {
      roomOptionKey(roomId: $0.roomId, floorId: $0.floorId) == roomKey && $0.finalRole == .primary
    }
    if !hasPrimaryInRoom {
      updated.finalRole = .primary
    } else if updated.finalRole == .primary {
      updated.finalRole = .detail
    }

    project.captures.removeAll { $0.id == updated.id }
    project.captures.append(updated)
    persistCaptures(&project)
  }

  private func beginEdit(_ take: VideoCaptureTake) {
    editTakeId = take.id
    editCaptureKind = take.kind
    editRoomOptionId = roomOptionKey(roomId: take.roomId, floorId: take.floorId)
    editFinalRole = take.finalRole
    editPriorityScore = take.priorityScore
    editSequenceIndex = max(1, take.sequenceIndex)
    editNote = take.editorNote
    if !availableRoomOptions.contains(where: { $0.id == editRoomOptionId }) {
      editRoomOptionId = availableRoomOptions.first?.id ?? ""
    }
    isEditTakePresented = true
  }

  private func applyEdit() {
    guard let editTakeId, var project else { return }
    guard let idx = project.captures.firstIndex(where: { $0.id == editTakeId }) else { return }

    project.captures[idx].kind = editCaptureKind
    if let option = roomOption(id: editRoomOptionId) {
      project.captures[idx].roomId = option.roomId
      project.captures[idx].floorId = option.floorId
    }
    project.captures[idx].finalRole = editFinalRole
    project.captures[idx].priorityScore = min(max(editPriorityScore, 1), 5)
    project.captures[idx].sequenceIndex = max(1, editSequenceIndex)
    project.captures[idx].editorNote = editNote.trimmingCharacters(in: .whitespacesAndNewlines)
    persistCaptures(&project)
  }

  private func deleteCapture(_ takeId: UUID) {
    guard var project else { return }
    guard let take = project.captures.first(where: { $0.id == takeId }) else { return }
    var videoURL: URL? = nil

    if let resolved = resolveURL(relativePath: take.videoRelativePath, projectId: project.id) {
      videoURL = resolved
      try? FileManager.default.removeItem(at: resolved)
    }
    if let motionURL = resolveURL(relativePath: take.motionRelativePath, projectId: project.id) {
      try? FileManager.default.removeItem(at: motionURL)
    }
    if let intrinsicsURL = resolveURL(relativePath: take.intrinsicsRelativePath, projectId: project.id) {
      try? FileManager.default.removeItem(at: intrinsicsURL)
    }
    if let trackingURL = resolveURL(relativePath: take.trackingRelativePath, projectId: project.id) {
      try? FileManager.default.removeItem(at: trackingURL)
    }
    if let videoURL {
      tryRemoveEmptyTakeFolder(forVideoURL: videoURL)
    }

    project.captures.removeAll { $0.id == takeId }
    persistCaptures(&project)
  }

  private func persistCaptures(_ project: inout VideoProject) {
    normalizeCaptureMetadata(&project)
    updateLegacyURLs(&project)
    self.project = project
    try? VideoProjectStore.saveCaptures(projectId: project.id, captures: project.captures)
  }

  private func normalizeCaptureMetadata(_ project: inout VideoProject) {
    guard !project.captures.isEmpty else { return }

    // Clamp values and ensure sane defaults.
    for idx in project.captures.indices {
      project.captures[idx].priorityScore = min(max(project.captures[idx].priorityScore, 1), 5)
      project.captures[idx].sequenceIndex = max(project.captures[idx].sequenceIndex, 1)
    }

    // Assign sequence if everything is unset/legacy.
    let hasMeaningfulSequence = project.captures.contains { $0.sequenceIndex > 1 }
    if !hasMeaningfulSequence {
      let orderedByTime = project.captures.sorted { $0.createdAt < $1.createdAt }
      for (idx, take) in orderedByTime.enumerated() {
        if let projectIdx = project.captures.firstIndex(where: { $0.id == take.id }) {
          project.captures[projectIdx].sequenceIndex = idx + 1
        }
      }
    }

    // Keep only one primary per room+floor and ensure at least one included take per room when possible.
    let grouped = Dictionary(grouping: project.captures.indices) { idx in
      roomOptionKey(roomId: project.captures[idx].roomId, floorId: project.captures[idx].floorId)
    }
    for (_, indices) in grouped {
      let primaryIndices = indices.filter { project.captures[$0].finalRole == .primary }
      if primaryIndices.count > 1 {
        let keep = primaryIndices.min { project.captures[$0].sequenceIndex < project.captures[$1].sequenceIndex } ?? primaryIndices[0]
        for idx in primaryIndices where idx != keep {
          project.captures[idx].finalRole = .detail
        }
      } else if primaryIndices.isEmpty {
        if let firstIncluded = indices
          .filter({ project.captures[$0].finalRole != .excluded })
          .min(by: { project.captures[$0].sequenceIndex < project.captures[$1].sequenceIndex }) {
          project.captures[firstIncluded].finalRole = .primary
        }
      }
    }

    // Re-number sequence to a dense range for predictable ordering.
    let ordered = project.captures.sorted { lhs, rhs in
      if lhs.sequenceIndex != rhs.sequenceIndex { return lhs.sequenceIndex < rhs.sequenceIndex }
      return lhs.createdAt < rhs.createdAt
    }
    for (idx, take) in ordered.enumerated() {
      if let projectIdx = project.captures.firstIndex(where: { $0.id == take.id }) {
        project.captures[projectIdx].sequenceIndex = idx + 1
      }
    }
  }

  private func primaryTakeBinding(for group: RoomCaptureGroup) -> Binding<String> {
    Binding<String>(
      get: {
        if let current = group.takes.first(where: { $0.finalRole == .primary }) {
          return current.id.uuidString
        }
        return group.takes.first?.id.uuidString ?? ""
      },
      set: { newValue in
        guard let takeId = UUID(uuidString: newValue) else { return }
        setPrimaryTake(roomId: group.roomId, floorId: group.floorId, takeId: takeId)
      }
    )
  }

  private func setPrimaryTake(roomId: String, floorId: String, takeId: UUID) {
    guard var project else { return }
    let roomKey = roomOptionKey(roomId: roomId, floorId: floorId)
    for idx in project.captures.indices {
      let key = roomOptionKey(roomId: project.captures[idx].roomId, floorId: project.captures[idx].floorId)
      guard key == roomKey else { continue }
      if project.captures[idx].id == takeId {
        project.captures[idx].finalRole = .primary
      } else if project.captures[idx].finalRole == .primary {
        project.captures[idx].finalRole = .detail
      }
    }
    persistCaptures(&project)
  }

  private func toggleCaptureIncluded(_ takeId: UUID) {
    guard var project else { return }
    guard let idx = project.captures.firstIndex(where: { $0.id == takeId }) else { return }

    if project.captures[idx].finalRole == .excluded {
      project.captures[idx].finalRole = .detail
      let roomId = project.captures[idx].roomId
      let floorId = project.captures[idx].floorId
      let roomKey = roomOptionKey(roomId: roomId, floorId: floorId)
      let hasPrimary = project.captures.contains {
        roomOptionKey(roomId: $0.roomId, floorId: $0.floorId) == roomKey && $0.finalRole == .primary
      }
      if !hasPrimary {
        project.captures[idx].finalRole = .primary
      }
    } else {
      project.captures[idx].finalRole = .excluded
    }
    persistCaptures(&project)
  }

  private func canMoveCapture(_ takeId: UUID, delta: Int) -> Bool {
    let ids = finalTimelineSorted.map(\.id)
    guard let idx = ids.firstIndex(of: takeId) else { return false }
    let target = idx + delta
    return target >= 0 && target < ids.count
  }

  private func moveCaptureInFinalOrder(_ takeId: UUID, delta: Int) {
    guard var project else { return }
    let ids = finalTimelineSorted.map(\.id)
    guard let idx = ids.firstIndex(of: takeId) else { return }
    let target = idx + delta
    guard target >= 0, target < ids.count else { return }
    let targetId = ids[target]

    guard let sourceIdx = project.captures.firstIndex(where: { $0.id == takeId }),
          let targetIdx = project.captures.firstIndex(where: { $0.id == targetId }) else { return }

    let old = project.captures[sourceIdx].sequenceIndex
    project.captures[sourceIdx].sequenceIndex = project.captures[targetIdx].sequenceIndex
    project.captures[targetIdx].sequenceIndex = old
    persistCaptures(&project)
  }

  private func updateLegacyURLs(_ project: inout VideoProject) {
    guard let preferred = project.preferredCapture else {
      project.mainVideoURL = nil
      project.motionCSVURL = nil
      project.intrinsicsJSONURL = nil
      project.trackingJSONURL = nil
      return
    }
    project.mainVideoURL = resolveURL(relativePath: preferred.videoRelativePath, projectId: project.id)
    project.motionCSVURL = resolveURL(relativePath: preferred.motionRelativePath, projectId: project.id)
    project.intrinsicsJSONURL = resolveURL(relativePath: preferred.intrinsicsRelativePath, projectId: project.id)
    project.trackingJSONURL = resolveURL(relativePath: preferred.trackingRelativePath, projectId: project.id)
  }

  private func migrateLegacyCaptureIfNeeded(_ project: inout VideoProject) {
    guard project.captures.isEmpty else { return }
    guard let paths = try? VideoProjectStore.createProjectPaths(projectId: project.id) else { return }
    let fm = FileManager.default
    guard fm.fileExists(atPath: paths.mainVideo.path) else { return }

    let attrs = try? fm.attributesOfItem(atPath: paths.mainVideo.path)
    let createdAt = (attrs?[.creationDate] as? Date) ?? (attrs?[.modificationDate] as? Date) ?? Date()
    let fallback = VideoCaptureTake(
      id: UUID(),
      createdAt: createdAt,
      kind: .walkthrough,
      roomId: RoomTaxonomy.defaultRoomId,
      floorId: FloorTaxonomy.defaultFloorId,
      videoRelativePath: "video/main_scan.mov",
      motionRelativePath: "sensors.csv",
      intrinsicsRelativePath: "intrinsics.json",
      trackingRelativePath: "tracking.json",
      durationSeconds: nil,
      finalRole: .primary,
      priorityScore: 4,
      sequenceIndex: 1
    )
    project.captures = [fallback]
    try? VideoProjectStore.saveCaptures(projectId: project.id, captures: project.captures)
  }

  private func resolveCaptureURL(relativePath: String) -> URL? {
    guard let project else { return nil }
    return resolveURL(relativePath: relativePath, projectId: project.id)
  }

  private func resolveURL(relativePath: String, projectId: UUID) -> URL? {
    guard let root = try? VideoProjectStore.createProjectPaths(projectId: projectId).root else { return nil }
    return root.appendingPathComponent(relativePath)
  }

  private func tryRemoveEmptyTakeFolder(forVideoURL videoURL: URL) {
    let folderURL = videoURL.deletingLastPathComponent()
    guard VideoProjectStore.isTakeFolderName(folderURL.lastPathComponent) else { return }
    try? FileManager.default.removeItem(at: folderURL)
  }

  private func manifestSubtitle() -> String {
    guard let project else { return l10n("video.workflow.manifest.subtitle.default") }
    guard let paths = try? VideoProjectStore.createProjectPaths(projectId: project.id) else {
      return l10n("video.workflow.manifest.subtitle.default")
    }
    if FileManager.default.fileExists(atPath: paths.manifestUPJ.path) {
      return l10n("video.workflow.manifest.subtitle.exists")
    }
    if project.captures.isEmpty {
      return l10n("video.workflow.manifest.subtitle.needsCapture")
    }
    return l10n("video.workflow.manifest.subtitle.default")
  }

  private func generateManifest() {
    ensureProject()
    guard let project else { return }
    guard let preferred = project.preferredCapture else {
      activeAlert = .manifestNeedsCapture
      return
    }

    do {
      let paths = try VideoProjectStore.createProjectPaths(projectId: project.id)
      let hasLidar = FileManager.default.fileExists(atPath: paths.lidarUSDZ.path)
      let hasVideo = FileManager.default.fileExists(atPath: paths.root.appendingPathComponent(preferred.videoRelativePath).path)
      let hasMotion = FileManager.default.fileExists(atPath: paths.root.appendingPathComponent(preferred.motionRelativePath).path)
      let hasIntrinsics = FileManager.default.fileExists(atPath: paths.root.appendingPathComponent(preferred.intrinsicsRelativePath).path)

      try UPJManifestWriter.write(
        projectId: project.id,
        outputURL: paths.manifestUPJ,
        includeLidar: hasLidar,
        includeVideo: hasVideo,
        includeMotion: hasMotion,
        includeIntrinsics: hasIntrinsics,
        includeAcoustics: false,
        mainVideoPath: preferred.videoRelativePath,
        motionDataPath: preferred.motionRelativePath,
        intrinsicsPath: preferred.intrinsicsRelativePath
      )
      manifestAlertText = l10n("video.workflow.manifest.created")
      activeAlert = .manifest
    } catch {
      manifestAlertText = error.localizedDescription
      activeAlert = .manifest
    }
  }

  private func roomOption(id: String) -> RoomFloorSelection? {
    availableRoomOptions.first(where: { $0.id == id })
  }

  private func roomOptionKey(roomId: String, floorId: String) -> String {
    "\(RoomTaxonomy.normalizedRoomId(roomId))|\(FloorTaxonomy.normalizedFloorId(floorId))"
  }

  private func captureDateText(_ date: Date) -> String {
    DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
  }

  private func loadOrCreateProjectId(for key: String) -> UUID {
    let defaults = UserDefaults.standard
    let storageKey = "video.project-id.\(sanitizeKey(key))"
    if let raw = defaults.string(forKey: storageKey), let uuid = UUID(uuidString: raw) {
      return uuid
    }
    let uuid = UUID()
    defaults.set(uuid.uuidString, forKey: storageKey)
    return uuid
  }

  private func sanitizeKey(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    let filtered = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    let collapsed = String(filtered).replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
    return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
  }

  private func presentJobPickerIfNeeded() {
    isJobPickerPresented = !hasProjectContext
  }

  private func applySelectedJob(_ job: JobInfo) {
    settings.setCurrentJob(job, userScope: authService.recentJobScope)
  }

  private struct CaptureRequest: Identifiable {
    let id = UUID()
    let takeId: UUID
    let kind: VideoCaptureKind
    let roomId: String
    let floorId: String
  }

  private struct RoomFloorSelection: Identifiable, Hashable {
    let roomId: String
    let floorId: String

    var id: String { "\(roomId)|\(floorId)" }
    var label: String {
      "\(RoomTaxonomy.room(id: roomId).displayName) · \(FloorTaxonomy.floor(id: floorId).shortDisplayName)"
    }
  }

  private struct RoomCaptureGroup: Identifiable, Hashable {
    let roomId: String
    let floorId: String
    let takes: [VideoCaptureTake]

    var id: String { "\(roomId)|\(floorId)" }
    var label: String {
      "\(RoomTaxonomy.room(id: roomId).displayName) · \(FloorTaxonomy.floor(id: floorId).shortDisplayName)"
    }
  }

  private enum WorkflowAlert: Identifiable {
    case manifest
    case manifestNeedsCapture

    var id: String {
      switch self {
      case .manifest:
        return "manifest"
      case .manifestNeedsCapture:
        return "manifestNeedsCapture"
      }
    }
  }

  private func l10n(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
  }
}
