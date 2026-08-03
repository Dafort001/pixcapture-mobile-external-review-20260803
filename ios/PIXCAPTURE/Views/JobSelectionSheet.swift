import SwiftUI

struct JobSelectionSheet: View {
  private enum Palette {
    static let background = Color.black
    static let darkBlue = Color(red: 42.0 / 255.0, green: 63.0 / 255.0, blue: 104.0 / 255.0)
    static let lightBlue = Color(red: 108.0 / 255.0, green: 168.0 / 255.0, blue: 200.0 / 255.0)
    static let orange = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let pink = Color(red: 227.0 / 255.0, green: 163.0 / 255.0, blue: 174.0 / 255.0)
    static let indigo = Color(red: 58.0 / 255.0, green: 70.0 / 255.0, blue: 124.0 / 255.0)
    static let utilityText = Color.white.opacity(0.56)
    static let bodyText = Color.white.opacity(0.78)
    static let cardText = Color.black.opacity(0.78)
    static let negative = Color(red: 1.0, green: 111.0 / 255.0, blue: 97.0 / 255.0)
  }

  @EnvironmentObject private var authService: AuthService
  @EnvironmentObject private var settings: AppSettings
  @Environment(\.dismiss) private var dismiss

  let title: String
  let subtitle: String?
  let allowsClear: Bool
  let clearLabel: String
  let requiresSelection: Bool
  let onSelect: (JobInfo) -> Void
  let onClear: () -> Void

  @State private var isCreatePresented = false
  @State private var jobPendingDeletion: JobInfo?
  @State private var jobEditing: JobInfo?
  @State private var isDeletingJob = false
  @State private var deleteMessage: String?

  private let cardColors: [Color] = [
    Palette.lightBlue,
    Palette.orange,
    Palette.pink,
    Palette.indigo
  ]

  private var displayedJobs: [JobInfo] {
    requiresSelection
      ? CaptureJobPolicy.regularCaptureJobs(from: authService.availableJobs)
      : authService.availableJobs
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        let logoWidth = min(geometry.size.width * 0.62, 290.0)
        let cardWidth = min(max(geometry.size.width * 0.76, 260.0), 420.0)
        let subtitleWidth = max(0.0, min(geometry.size.width - 56.0, 430.0))
        let noteWidth = max(0.0, min(geometry.size.width - 64.0, 420.0))
        let titleTopSpacing = max(34.0, geometry.size.height * 0.05)
        let footerSpacing = max(20.0, geometry.safeAreaInsets.bottom + 10.0)

        ZStack {
          Palette.background
            .ignoresSafeArea()

          VStack(spacing: 0) {
            topUtilityBar
              .padding(.top, max(geometry.safeAreaInsets.top + 10.0, 18.0))

            ScrollView(showsIndicators: false) {
              VStack(spacing: 0) {
                Spacer(minLength: titleTopSpacing)

                Image("AppLogo")
                  .resizable()
                  .renderingMode(.original)
                  .scaledToFit()
                  .frame(width: logoWidth)
                  .accessibilityLabel(l10n("start.logo.accessibility"))

                VStack(spacing: 12) {
                  Text(title.uppercased())
                    .font(inter(size: 22, weight: .light))
                    .tracking(1.0)
                    .foregroundStyle(.white)

                  if let subtitle,
                     !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                      .font(inter(size: 14, weight: .light))
                      .tracking(0.3)
                      .multilineTextAlignment(.center)
                      .foregroundStyle(Palette.utilityText)
                      .frame(maxWidth: subtitleWidth)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
                .padding(.top, 36)

                VStack(spacing: 16) {
                  primaryCreateButton(width: cardWidth)

                  if displayedJobs.isEmpty {
                    emptyStateCard(width: cardWidth)
                  } else {
                    ForEach(Array(displayedJobs.enumerated()), id: \.element.id) { index, job in
                      jobCard(job, index: index, width: cardWidth)
                    }
                  }
                }
                .padding(.top, 42)

                if let deleteMessage,
                   !deleteMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  Text(deleteMessage)
                    .font(inter(size: 12, weight: .regular))
                    .tracking(0.2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.utilityText)
                    .frame(maxWidth: noteWidth)
                    .padding(.top, 18)
                }

                if !displayedJobs.isEmpty {
                  Text(l10n("jobs.sheet.note"))
                    .font(inter(size: 11, weight: .light))
                    .tracking(0.3)
                    .foregroundStyle(Palette.utilityText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: noteWidth)
                    .padding(.top, 22)
                }

                if allowsClear {
                  Button(clearLabel.uppercased()) {
                    onClear()
                    dismiss()
                  }
                  .buttonStyle(.plain)
                  .font(inter(size: 12, weight: .regular))
                  .tracking(1.0)
                  .foregroundStyle(Palette.negative)
                  .accessibilityIdentifier("jobs.clear")
                  .padding(.top, 26)
                }

                Spacer(minLength: footerSpacing)
              }
              .frame(maxWidth: .infinity)
              .padding(.horizontal, 28)
            }
          }
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .task {
        await authService.refreshJobs()
      }
      .onChange(of: authService.requiresInteractiveLogin) { _, requiresLogin in
        guard requiresLogin else { return }
        isCreatePresented = false
        jobPendingDeletion = nil
        jobEditing = nil
        hideSystemKeyboard()
        dismiss()
      }
      .alert(
        jobPendingDeletion == nil ? l10n("jobs.delete.title") : l10n("jobs.delete.confirmTitle"),
        isPresented: Binding(
          get: { jobPendingDeletion != nil },
          set: { isPresented in
            if !isPresented {
              jobPendingDeletion = nil
            }
          }
        ),
        presenting: jobPendingDeletion
      ) { job in
        Button(l10n("common.cancel"), role: .cancel) {}
        Button(l10n("jobs.delete.button"), role: .destructive) {
          Task {
            await deleteJob(job)
          }
        }
      } message: { job in
        Text(l10nFormat("jobs.delete.message.format", job.name))
      }
      .sheet(isPresented: $isCreatePresented) {
        JobCreateSheet(
          onSaved: { created in
            onSelect(created)
            dismiss()
          }
        )
        .environmentObject(authService)
        .environmentObject(settings)
      }
      .sheet(item: $jobEditing) { job in
        JobCreateSheet(
          editingJob: job,
          onSaved: { updated in
            onSelect(updated)
            jobEditing = nil
          }
        )
        .environmentObject(authService)
        .environmentObject(settings)
      }
    }
    .interactiveDismissDisabled(requiresSelection)
  }

  private var topUtilityBar: some View {
    HStack {
      Spacer()

      if !requiresSelection {
        Button {
          dismiss()
        } label: {
          PixDonePill(title: l10n("common.done"))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n("common.done"))
      }
    }
  }

  private func primaryCreateButton(width: CGFloat) -> some View {
    Button {
      isCreatePresented = true
    } label: {
      ZStack {
        Rectangle()
          .fill(Palette.orange)
          .frame(width: width, height: 84)

        Text(l10n("jobs.create.button"))
          .font(inter(size: 20, weight: .light))
          .tracking(0.9)
          .foregroundStyle(Palette.cardText)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("jobs.create.open")
  }

  private func emptyStateCard(width: CGFloat) -> some View {
    VStack(spacing: 8) {
      Text(l10n("jobs.empty.title"))
        .font(inter(size: 17, weight: .light))
        .tracking(0.8)
        .foregroundStyle(Palette.darkBlue)

      Text(l10n("jobs.empty.subtitle"))
        .font(inter(size: 13, weight: .light))
        .tracking(0.2)
        .multilineTextAlignment(.center)
        .foregroundStyle(Palette.darkBlue.opacity(0.9))
        .frame(maxWidth: max(0.0, width - 48.0))
    }
    .frame(width: width)
    .frame(minHeight: 112)
    .padding(.vertical, 14)
    .background(Palette.lightBlue)
  }

  private func jobCard(_ job: JobInfo, index: Int, width: CGFloat) -> some View {
    let fill = cardFill(for: index)
    let textColor = cardTextColor(for: index)

    return ZStack(alignment: .topTrailing) {
      Button {
        onSelect(job)
        dismiss()
      } label: {
        ZStack {
          Rectangle()
            .fill(fill)
            .frame(width: width)

          VStack(spacing: 8) {
            Text(job.name.uppercased())
              .font(inter(size: 19, weight: .light))
              .tracking(0.9)
              .foregroundStyle(textColor)
              .multilineTextAlignment(.center)
              .lineLimit(2)

            if let propertyAddress = job.propertyAddress,
               !propertyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text(propertyAddress)
                .font(inter(size: 12, weight: .light))
                .tracking(0.2)
                .foregroundStyle(textColor.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: max(0.0, width - 42.0))
            } else {
              Text(l10n("jobs.noAddress"))
                .font(inter(size: 12, weight: .light))
                .tracking(0.2)
                .foregroundStyle(textColor.opacity(0.72))
            }
          }
          .padding(.horizontal, 18)
          .padding(.vertical, 18)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("job.card.\(job.id)")
      .disabled(isDeletingJob)

      HStack(spacing: 0) {
        Button {
          deleteMessage = nil
          jobEditing = job
        } label: {
          Image(systemName: "pencil.circle.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(textColor.opacity(0.86))
            .padding(10)
        }
        .buttonStyle(.plain)
        .disabled(isDeletingJob)

        Button {
          deleteMessage = nil
          jobPendingDeletion = job
        } label: {
          Image(systemName: "trash.circle.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(textColor.opacity(0.86))
            .padding(10)
        }
        .buttonStyle(.plain)
        .disabled(isDeletingJob)
      }
    }
  }

  private func cardFill(for index: Int) -> Color {
    cardColors[index % cardColors.count]
  }

  private func cardTextColor(for index: Int) -> Color {
    switch index % cardColors.count {
    case 0:
      return Palette.darkBlue
    case 1:
      return Palette.cardText
    case 2:
      return Palette.darkBlue
    default:
      return Palette.pink
    }
  }

  private func deleteJob(_ job: JobInfo) async {
    guard !isDeletingJob else { return }
    isDeletingJob = true
    let didDelete = await authService.deleteJob(id: job.id)
    isDeletingJob = false
    if didDelete {
      jobPendingDeletion = nil
      deleteMessage = authService.lastInfoMessage
      await authService.refreshJobs()
    } else {
      deleteMessage = authService.lastError ?? l10n("jobs.delete.error")
    }
  }

  private func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .pixInter(size: size, weight: weight)
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }

  private func l10nFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalizer.localizedFormat(key, language: settings.appLanguage, arguments: arguments)
  }
}

private struct JobCreateSheet: View {
  private enum Field: Hashable {
    case title
    case address
  }

  private enum Palette {
    static let background = Color.black
    static let orange = Color(red: 209.0 / 255.0, green: 94.0 / 255.0, blue: 64.0 / 255.0)
    static let utilityText = Color.white.opacity(0.56)
    static let fieldText = orange
    static let line = orange
    static let errorText = Color(red: 1.0, green: 111.0 / 255.0, blue: 97.0 / 255.0)
  }

  @EnvironmentObject private var authService: AuthService
  @EnvironmentObject private var settings: AppSettings
  @Environment(\.dismiss) private var dismiss

  let editingJob: JobInfo?
  let onSaved: (JobInfo) -> Void

  @State private var title = ""
  @State private var address = ""
  @State private var isSaving = false
  @State private var createError: String?
  @FocusState private var focusedField: Field?

  init(editingJob: JobInfo? = nil, onSaved: @escaping (JobInfo) -> Void) {
    self.editingJob = editingJob
    self.onSaved = onSaved
    _title = State(initialValue: editingJob?.name ?? "")
    _address = State(initialValue: editingJob?.propertyAddress ?? "")
  }

  var body: some View {
    GeometryReader { geometry in
      let logoWidth = min(geometry.size.width * 0.58, 260.0)
      let fieldWidth = max(0.0, min(geometry.size.width - 64.0, 360.0))
      let subtitleWidth = max(0.0, min(geometry.size.width - 56.0, 420.0))
      let errorWidth = max(0.0, min(geometry.size.width - 72.0, 380.0))
      let topInset = max(geometry.safeAreaInsets.top + 26.0, 36.0)

      ZStack {
        Palette.background
          .ignoresSafeArea()

        VStack(spacing: 0) {
          HStack {
            Spacer()

            Button(l10n("common.cancel").uppercased()) {
              dismiss()
            }
            .buttonStyle(.plain)
            .font(inter(size: 10, weight: .regular))
            .tracking(1.3)
            .foregroundStyle(Palette.utilityText)
          }
          .padding(.top, topInset)
          .padding(.horizontal, 28)

          Spacer(minLength: max(28.0, geometry.size.height * 0.05))

          Image("AppLogo")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: logoWidth)
            .accessibilityLabel(l10n("start.logo.accessibility"))

          VStack(spacing: 12) {
            Text(editingJob == nil ? l10n("jobs.create.title") : l10n("jobs.edit.title"))
              .font(inter(size: 22, weight: .light))
              .tracking(1.0)
              .foregroundStyle(.white)

            Text(l10n("jobs.create.subtitle"))
              .font(inter(size: 14, weight: .light))
              .tracking(0.2)
              .multilineTextAlignment(.center)
              .foregroundStyle(Palette.utilityText)
              .frame(maxWidth: subtitleWidth)
          }
          .padding(.top, 34)

          VStack(spacing: 44) {
            underlineField(
              placeholder: l10n("jobs.create.namePlaceholder"),
              text: $title,
              field: .title,
              submitLabel: .next
            ) {
              focusedField = .address
            }

            underlineField(
              placeholder: l10n("jobs.create.addressPlaceholder"),
              text: $address,
              field: .address,
              submitLabel: .done
            ) {
              Task {
                await saveJob()
              }
            }
          }
          .frame(width: fieldWidth)
          .padding(.top, 54)

          if let createError,
             !createError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(createError)
              .font(inter(size: 12, weight: .light))
              .tracking(0.2)
              .multilineTextAlignment(.center)
              .foregroundStyle(Palette.errorText)
              .frame(maxWidth: errorWidth)
              .padding(.top, 26)
          }

          Spacer(minLength: 28)

          Button {
            Task {
              await saveJob()
            }
          } label: {
            ZStack {
              Rectangle()
                .fill(Palette.orange)
                .frame(width: fieldWidth, height: 78)

              if isSaving {
                ProgressView()
                  .tint(.black.opacity(0.78))
              } else {
                Text(l10n("common.save").uppercased())
                  .font(inter(size: 19, weight: .light))
                  .tracking(0.9)
                  .foregroundStyle(Color.black.opacity(0.82))
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("jobs.create.save")
          .disabled(
            isSaving
              || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          .opacity(
            isSaving
              || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? 0.62 : 1.0
          )
          .padding(.bottom, geometry.safeAreaInsets.bottom + 22.0)
        }
      }
    }
    .dismissKeyboardOnTap()
    .keyboardDoneToolbar()
    .onChange(of: authService.requiresInteractiveLogin) { _, requiresLogin in
      guard requiresLogin else { return }
      focusedField = nil
      hideSystemKeyboard()
      dismiss()
    }
  }

  private func underlineField(
    placeholder: String,
    text: Binding<String>,
    field: Field,
    submitLabel: SubmitLabel,
    onSubmit: @escaping () -> Void
  ) -> some View {
    VStack(spacing: 14) {
      TextField(
        "",
        text: text,
        prompt: Text(placeholder).foregroundStyle(Palette.fieldText)
      )
      .textInputAutocapitalization(.words)
      .autocorrectionDisabled(false)
      .focused($focusedField, equals: field)
      .submitLabel(submitLabel)
      .onSubmit(onSubmit)
      .multilineTextAlignment(.center)
      .font(inter(size: 18, weight: .light))
      .tracking(0.9)
      .foregroundStyle(Palette.fieldText)
      .accessibilityIdentifier(field == .title ? "jobs.create.name" : "jobs.create.address")

      Rectangle()
        .fill(Palette.line)
        .frame(height: 1.5)
    }
  }

  private func saveJob() async {
    guard !isSaving else { return }
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    focusedField = nil
    hideSystemKeyboard()
    isSaving = true
    createError = nil
    let saved: JobInfo?
    if let editingJob {
      saved = await authService.updateJob(
        id: editingJob.id,
        title: title,
        propertyAddress: address,
        notes: nil
      )
    } else {
      saved = await authService.createJob(
        title: title,
        propertyAddress: address,
        notes: nil
      )
    }
    isSaving = false

    guard let saved else {
      createError = authService.lastError ?? l10n("jobs.create.error")
      return
    }

    onSaved(saved)
    dismiss()
  }

  private func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .pixInter(size: size, weight: weight)
  }

  private func l10n(_ key: String) -> String {
    settings.localized(key)
  }
}
