import SwiftUI
import MapKit
import CoreLocation
import Combine

struct SunPlanView: View {
  private enum FocusedField: Hashable {
    case street
    case locality
  }

  private enum Palette {
    static let background = PixBrand.background
    static let panel = PixBrand.panel
    static let title = PixBrand.textOnDark
    static let body = PixBrand.textOnDarkSecondary
    static let border = PixBrand.borderOnDark
    static let blueCard = Color(red: 0.82, green: 0.91, blue: 0.98)
    static let pinkCard = Color(red: 0.97, green: 0.88, blue: 0.92)
    static let warmCard = Color(red: 0.98, green: 0.92, blue: 0.84)
    static let indigoCard = Color(red: 0.89, green: 0.90, blue: 0.98)
    static let onLightPrimary = Color.black.opacity(0.84)
    static let onLightSecondary = Color.black.opacity(0.60)
    static let onLightTertiary = Color.black.opacity(0.46)
  }

  var onNavigate: (AppScreen) -> Void

  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var authService: AuthService

  @StateObject private var viewModel = SunPlanViewModel()
  @State private var mapPosition: MapCameraPosition = .automatic
  @State private var mapVisibleMeters: Double = 260
  @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
  @State private var selectedMinute: Double = -1
  @State private var facadeBearing: Double = 180
  @State private var hasLoadedStoredState = false
  @FocusState private var focusedField: FocusedField?

  @AppStorage("sunPlan.query") private var storedQuery: String = ""
  @AppStorage("sunPlan.localityHint") private var storedLocalityHint: String = ""
  @AppStorage("sunPlan.latitude") private var storedLatitude: Double = 0
  @AppStorage("sunPlan.longitude") private var storedLongitude: Double = 0
  @AppStorage("sunPlan.hasCoordinate") private var storedHasCoordinate: Bool = false
  @AppStorage("sunPlan.date") private var storedDateInterval: Double = Date().timeIntervalSince1970
  @AppStorage("sunPlan.selectedMinute") private var storedSelectedMinute: Double = -1
  @AppStorage("sunPlan.facadeBearing") private var storedFacadeBearing: Double = 180

  private var selectedJob: JobInfo? {
    guard let selectedJobId = settings.selectedJobId else { return nil }
    return authService.availableJobs.first(where: { $0.id == selectedJobId })
  }

  private var suggestedAddress: String {
    let candidates = [
      selectedJob?.propertyAddress,
      settings.jobAddress,
      settings.jobLabel
    ]
    for candidate in candidates {
      let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !trimmed.isEmpty {
        return trimmed
      }
    }
    return ""
  }

  private var solarDay: SolarDaySummary? {
    guard let coordinate = viewModel.coordinate else { return nil }
    return SolarCalculator.makeDaySummary(
      for: selectedDate,
      coordinate: coordinate,
      timeZone: .current
    )
  }

  private var currentSolarPosition: SolarPosition? {
    guard let solarDay,
          selectedMinute >= solarDay.sunriseMinute,
          selectedMinute <= solarDay.sunsetMinute else { return nil }
    return solarDay.position(atMinute: selectedMinute)
  }

  private var bestWindow: SunLightWindow? {
    guard let solarDay else { return nil }
    return SolarCalculator.bestWindow(for: solarDay, facadeBearing: facadeBearing)
  }

  private var currentAssessment: SunLightAssessment? {
    guard let currentSolarPosition else { return nil }
    return SolarCalculator.assessment(
      for: currentSolarPosition,
      facadeBearing: facadeBearing
    )
  }

  private var mapMarkers: [SunMapMarker] {
    guard let solarDay else { return [] }
    var markers: [SunMapMarker] = []

    let sunrise = solarDay.position(atMinute: solarDay.sunriseMinute)
    markers.append(
      SunMapMarker(
        id: "sunrise",
        coordinate: SolarMapProjection.coordinate(
          from: solarDay.coordinate,
          azimuthDegrees: sunrise.azimuthDegrees,
          elevationDegrees: sunrise.elevationDegrees,
          maxRadiusMeters: 220
        ),
        label: "Sunrise",
        secondaryLabel: timeString(forMinute: solarDay.sunriseMinute),
        tint: Color.orange,
        prominence: .normal
      )
    )

    let noon = solarDay.position(atMinute: solarDay.solarNoonMinute)
    markers.append(
      SunMapMarker(
        id: "noon",
        coordinate: SolarMapProjection.coordinate(
          from: solarDay.coordinate,
          azimuthDegrees: noon.azimuthDegrees,
          elevationDegrees: noon.elevationDegrees,
          maxRadiusMeters: 220
        ),
        label: "Mittag",
        secondaryLabel: timeString(forMinute: solarDay.solarNoonMinute),
        tint: Color.yellow.opacity(0.92),
        prominence: .compact
      )
    )

    let sunset = solarDay.position(atMinute: solarDay.sunsetMinute)
    markers.append(
      SunMapMarker(
        id: "sunset",
        coordinate: SolarMapProjection.coordinate(
          from: solarDay.coordinate,
          azimuthDegrees: sunset.azimuthDegrees,
          elevationDegrees: sunset.elevationDegrees,
          maxRadiusMeters: 220
        ),
        label: "Sunset",
        secondaryLabel: timeString(forMinute: solarDay.sunsetMinute),
        tint: Color.red.opacity(0.88),
        prominence: .normal
      )
    )

    if let currentSolarPosition {
      markers.append(
        SunMapMarker(
          id: "current",
          coordinate: SolarMapProjection.coordinate(
            from: solarDay.coordinate,
            azimuthDegrees: currentSolarPosition.azimuthDegrees,
            elevationDegrees: currentSolarPosition.elevationDegrees,
            maxRadiusMeters: 220
          ),
          label: timeString(forMinute: selectedMinute),
          secondaryLabel: "Aktuell",
          tint: Color(red: 1.0, green: 0.83, blue: 0.18),
          prominence: .highlight
        )
      )
    }

    return markers
  }

  private var pathPolyline: MKPolyline? {
    guard let solarDay else { return nil }
    let coordinates = solarDay.pathCoordinates(maxRadiusMeters: 220)
    guard coordinates.count >= 2 else { return nil }
    return MKPolyline(coordinates: coordinates, count: coordinates.count)
  }

  private var currentSunPolyline: MKPolyline? {
    guard let solarDay, let currentSolarPosition else { return nil }
    let point = SolarMapProjection.coordinate(
      from: solarDay.coordinate,
      azimuthDegrees: currentSolarPosition.azimuthDegrees,
      elevationDegrees: currentSolarPosition.elevationDegrees,
      maxRadiusMeters: 220
    )
    let coordinates = [solarDay.coordinate, point]
    return MKPolyline(coordinates: coordinates, count: coordinates.count)
  }

  private var facadePolyline: MKPolyline? {
    guard let solarDay else { return nil }
    let point = SolarMapProjection.destinationCoordinate(
      from: solarDay.coordinate,
      bearingDegrees: facadeBearing,
      distanceMeters: 130
    )
    let coordinates = [solarDay.coordinate, point]
    return MKPolyline(coordinates: coordinates, count: coordinates.count)
  }

  var body: some View {
    ZStack {
      Palette.background.ignoresSafeArea()

      VStack(spacing: 0) {
        header

        ScrollView {
          VStack(spacing: 16) {
            addressCard

            if let solarDay {
              sunInsightsCard(for: solarDay)
              mapCard(for: solarDay)
              timelineCard(for: solarDay)
              facadeCard
            } else {
              emptyStateCard
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 14)
          .padding(.bottom, 124)
        }
        .scrollDismissesKeyboard(.interactively)

        BottomNavBar(selected: .sunPlan) { tab in
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
        .frame(maxWidth: .infinity)
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Fertig") {
          dismissKeyboard()
        }
      }
    }
    .task {
      guard !hasLoadedStoredState else { return }
      hasLoadedStoredState = true
      selectedDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: storedDateInterval))
      facadeBearing = normalizedBearing(storedFacadeBearing)
      selectedMinute = storedSelectedMinute

      let restoredCoordinate = storedHasCoordinate
        ? CLLocationCoordinate2D(latitude: storedLatitude, longitude: storedLongitude)
        : nil
      let prefillQuery = storedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? SunPlanViewModel.primaryAddressLine(from: suggestedAddress)
        : storedQuery
      let prefillLocalityHint = storedLocalityHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? SunPlanViewModel.secondaryAddressLine(from: suggestedAddress)
        : storedLocalityHint
      viewModel.restore(query: prefillQuery, localityHint: prefillLocalityHint, coordinate: restoredCoordinate)

      if let restoredCoordinate {
        moveMap(to: restoredCoordinate)
      } else if let propertyAddress = selectedJob?.propertyAddress,
                !propertyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                storedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        await runGeocode()
      }

      syncSelectedMinute()
    }
    .onChange(of: viewModel.coordinate?.latitude) { _, _ in
      persistLocation()
      if let coordinate = viewModel.coordinate {
        moveMap(to: coordinate)
      }
      syncSelectedMinute()
    }
    .onChange(of: viewModel.coordinate?.longitude) { _, _ in
      persistLocation()
      syncSelectedMinute()
    }
    .onChange(of: selectedDate) { _, newValue in
      let normalized = Calendar.current.startOfDay(for: newValue)
      if normalized != newValue {
        selectedDate = normalized
        return
      }
      storedDateInterval = normalized.timeIntervalSince1970
      syncSelectedMinute()
    }
    .onChange(of: selectedMinute) { _, newValue in
      storedSelectedMinute = newValue
    }
    .onChange(of: facadeBearing) { _, newValue in
      storedFacadeBearing = normalizedBearing(newValue)
    }
    .onChange(of: mapVisibleMeters) { _, _ in
      if let coordinate = viewModel.coordinate {
        moveMap(to: coordinate, animated: true)
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Button {
          onNavigate(.start)
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.title)
            .frame(width: 34, height: 34)
            .background(Palette.panel)
            .clipShape(PixBrand.tileShape())
            .overlay(PixBrand.tileShape().stroke(Palette.border, lineWidth: 1))
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Zur Startseite")

        Spacer()

        VStack(alignment: .trailing, spacing: 2) {
          Text("Sonnenstand")
            .font(.pixInter(size: 22, weight: .light))
            .tracking(0.7)
            .foregroundStyle(Palette.title)
          Text("Sonnenbahn und passende Uhrzeit")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.body)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
    .padding(.bottom, 8)
  }

  private var addressCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Objektadresse")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Palette.onLightPrimary)
        Spacer()
        if let selectedJob {
          Text(selectedJob.name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.onLightTertiary)
        }
      }

      HStack(spacing: 10) {
        TextField(
          "",
          text: $viewModel.query,
          prompt: Text("Adresse oder Objekt eingeben")
            .foregroundStyle(Palette.onLightSecondary)
        )
          .textInputAutocapitalization(.words)
          .disableAutocorrection(true)
          .submitLabel(.search)
          .foregroundStyle(Palette.onLightPrimary)
          .tint(AppTheme.primary)
          .focused($focusedField, equals: .street)
          .onSubmit {
            Task { await runGeocode() }
          }

        Button {
          Task { await runGeocode() }
        } label: {
          if viewModel.isSearching {
            ProgressView()
              .tint(.white)
              .frame(width: 18, height: 18)
          } else {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 14, weight: .semibold))
          }
        }
        .disabled(viewModel.isSearching || viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
        .background(AppTheme.primary)
        .clipShape(PixBrand.tileShape())
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(Color.white)
      .clipShape(PixBrand.tileShape())
      .overlay(
        PixBrand.tileShape()
          .stroke(Color.black.opacity(0.08), lineWidth: 1)
      )

      TextField(
        "",
        text: $viewModel.localityHint,
        prompt: Text("PLZ, Ort oder Land (optional)")
          .foregroundStyle(Palette.onLightSecondary)
      )
        .textInputAutocapitalization(.words)
        .disableAutocorrection(true)
        .submitLabel(.search)
        .foregroundStyle(Palette.onLightPrimary)
        .tint(AppTheme.primary)
        .focused($focusedField, equals: .locality)
        .onSubmit {
          Task { await runGeocode() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(PixBrand.tileShape())
        .overlay(
          PixBrand.tileShape()
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )

      Text("Mit PLZ oder Ort wird die Suche deutlich genauer. Sonst kann dieselbe Straße auch in einer anderen Stadt landen.")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.onLightSecondary)

      if let resolvedPlace = viewModel.resolvedPlaceName,
         !resolvedPlace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Label(resolvedPlace, systemImage: "mappin.and.ellipse")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Palette.onLightSecondary)
      } else if !suggestedAddress.isEmpty && viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Label("Job-Adresse übernommen: \(suggestedAddress)", systemImage: "building.2")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Palette.onLightSecondary)
      }

      if let errorMessage = viewModel.errorMessage,
         !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(errorMessage)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.red.opacity(0.88))
      }
    }
    .padding(16)
    .background(Palette.warmCard)
    .clipShape(PixBrand.tileShape())
    .overlay(PixBrand.tileShape().stroke(Color.black.opacity(0.06), lineWidth: 1))
    .environment(\.colorScheme, .light)
  }

  private func mapCard(for solarDay: SolarDaySummary) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Sonnenbahn auf Satellitenbild")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.82))
        Spacer()
        if let currentSolarPosition {
          Text("Az \(Int(currentSolarPosition.azimuthDegrees.rounded()))° • Hoehe \(Int(currentSolarPosition.elevationDegrees.rounded()))°")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.48))
        }
      }

      ZStack(alignment: .topLeading) {
        Map(position: $mapPosition, interactionModes: [.all]) {
          if let pathPolyline {
            MapPolyline(pathPolyline)
              .stroke(Color.orange.opacity(0.78), lineWidth: 4)
          }

          if let currentSunPolyline {
            MapPolyline(currentSunPolyline)
              .stroke(
                Color(red: 1.0, green: 0.83, blue: 0.18),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 7])
              )
          }

          if let facadePolyline {
            MapPolyline(facadePolyline)
              .stroke(
                Color(red: 0.12, green: 0.43, blue: 0.89).opacity(0.9),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 4])
              )
          }

          Annotation("Objekt", coordinate: solarDay.coordinate, anchor: .center) {
            ZStack {
              Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
              Circle()
                .fill(Color(red: 0.24, green: 0.28, blue: 0.24))
                .frame(width: 10, height: 10)
            }
            .overlay(
              Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: 10)
                .blur(radius: 8)
            )
          }

          ForEach(mapMarkers) { marker in
            Annotation(marker.label, coordinate: marker.coordinate, anchor: .center) {
              SunMapMarkerView(marker: marker)
            }
          }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .frame(height: 360)
        .clipShape(PixBrand.tileShape())

        VStack(alignment: .leading, spacing: 8) {
          badge(title: "Sunrise", value: timeString(forMinute: solarDay.sunriseMinute), tint: Color.orange)
          badge(title: "Sunset", value: timeString(forMinute: solarDay.sunsetMinute), tint: Color.red.opacity(0.82))
          badge(title: "Objektseite", value: "\(compassLabel(for: facadeBearing)) • \(Int(facadeBearing.rounded()))°", tint: Color.blue.opacity(0.78))
        }
        .padding(12)

        VStack(spacing: 8) {
          mapZoomButton(systemName: "plus") {
            mapVisibleMeters = max(90, mapVisibleMeters * 0.62)
          }
          mapZoomButton(systemName: "minus") {
            mapVisibleMeters = min(1_600, mapVisibleMeters * 1.6)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      }

      Text("Orange zeigt den Tagesbogen. Gelb zeigt die gewählte Uhrzeit, Blau die Objektseite bzw. Blickrichtung.")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.58))
    }
    .padding(16)
    .background(Palette.blueCard)
    .clipShape(PixBrand.tileShape())
    .overlay(
      PixBrand.tileShape()
        .stroke(Color.black.opacity(0.06), lineWidth: 1)
    )
    .environment(\.colorScheme, .light)
  }

  private func sunInsightsCard(for solarDay: SolarDaySummary) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Sonnenstand-Hinweise")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
          Text("Kurzcheck fuer Sonnenbahn, Fassadenseite und Aufnahmezeit")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
        }

        Spacer()
      }

      HStack(alignment: .center, spacing: 14) {
        Image(systemName: currentAssessment?.symbolName ?? "sun.max.fill")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(currentAssessment?.tint ?? AppTheme.accent)
          .frame(width: 46, height: 46)
          .background((currentAssessment?.tint ?? AppTheme.accent).opacity(0.12))
          .clipShape(PixBrand.tileShape())

        VStack(alignment: .leading, spacing: 2) {
          Text(currentAssessment?.title ?? "Sonne planen")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
          Text(currentAssessment?.subtitle ?? "Waehle eine Uhrzeit und die Objektseite, um das Licht vor Ort besser einzuschaetzen.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
        }

        Spacer()
      }

      HStack(spacing: 10) {
        sunMetricTile(
          title: "Beste Zeit",
          value: bestWindow.map { "\(timeString(forMinute: $0.startMinute))-\(timeString(forMinute: $0.endMinute))" } ?? "\(timeString(forMinute: solarDay.sunriseMinute))-\(timeString(forMinute: solarDay.sunsetMinute))",
          symbol: "clock.badge.checkmark",
          tint: bestWindow?.tint ?? AppTheme.accent
        )
        sunMetricTile(
          title: "Objektseite",
          value: "\(compassLabel(for: facadeBearing)) \(Int(facadeBearing.rounded()))°",
          symbol: "safari",
          tint: AppTheme.primary
        )
        sunMetricTile(
          title: "Sonne",
          value: currentSolarPosition.map { "\(Int($0.elevationDegrees.rounded()))° hoch" } ?? "ausserhalb",
          symbol: "sun.max",
          tint: currentAssessment?.tint ?? AppTheme.secondary
        )
      }

      if let bestWindow {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "sparkles")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(bestWindow.tint)

          VStack(alignment: .leading, spacing: 2) {
            Text(bestWindow.title)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(AppTheme.textPrimary)
            Text(bestWindow.reason)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(AppTheme.textSecondary)
          }
        }
        .padding(12)
        .background(Color.white.opacity(0.8))
        .clipShape(PixBrand.tileShape())
      } else {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "sun.max.trianglebadge.exclamationmark")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.secondary)
            .frame(width: 24, height: 24)
          Text("Fuer diese Objektseite gibt es heute kein klares direktes Lichtfenster. Nutze Karte und Uhrzeit-Regler, um einen brauchbaren Kompromiss zu finden.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.8))
        .clipShape(PixBrand.tileShape())
      }
    }
    .padding(16)
    .background(Palette.pinkCard)
    .clipShape(PixBrand.tileShape())
    .overlay(
      PixBrand.tileShape()
        .stroke(AppTheme.stroke, lineWidth: 1)
    )
    .environment(\.colorScheme, .light)
  }

  private func timelineCard(for solarDay: SolarDaySummary) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Datum und Uhrzeit")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))

      DatePicker(
        "Tag",
        selection: $selectedDate,
        displayedComponents: [.date]
      )
      .datePickerStyle(.compact)
      .foregroundStyle(Palette.onLightPrimary)
      .tint(AppTheme.primary)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Zeit")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.72))
          Spacer()
          Text(timeString(forMinute: selectedMinute))
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.86))
        }

        Slider(
          value: Binding(
            get: { selectedMinute },
            set: { selectedMinute = min(max($0, solarDay.sunriseMinute), solarDay.sunsetMinute) }
          ),
          in: solarDay.sunriseMinute...solarDay.sunsetMinute,
          step: 5
        )
        .tint(Color(red: 0.96, green: 0.72, blue: 0.12))

        HStack {
          Text(timeString(forMinute: solarDay.sunriseMinute))
          Spacer()
          Text(timeString(forMinute: solarDay.solarNoonMinute))
          Spacer()
          Text(timeString(forMinute: solarDay.sunsetMinute))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.5))
      }

      if let currentAssessment {
        HStack(spacing: 10) {
          Image(systemName: currentAssessment.symbolName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(currentAssessment.tint)
          VStack(alignment: .leading, spacing: 2) {
            Text(currentAssessment.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.82))
            Text(currentAssessment.subtitle)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(Color.black.opacity(0.56))
          }
        }
      }
    }
    .padding(16)
    .background(Palette.indigoCard)
    .clipShape(PixBrand.tileShape())
    .overlay(
      PixBrand.tileShape()
        .stroke(Color.black.opacity(0.06), lineWidth: 1)
    )
    .environment(\.colorScheme, .light)
  }

  private var facadeCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Objektseite / Blickrichtung")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))

      Text("Richte den Regler auf die Fassadenseite oder die Blickrichtung der geplanten Aufnahme. Dadurch kann die App besser zwischen Vormittag und Nachmittag unterscheiden.")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.58))

      HStack {
        Text(compassLabel(for: facadeBearing))
          .font(.system(size: 28, weight: .semibold, design: .rounded))
          .foregroundStyle(Color.black.opacity(0.82))
        Spacer()
        Text("\(Int(facadeBearing.rounded()))°")
          .font(.system(size: 20, weight: .semibold, design: .rounded))
          .foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.89))
      }

      Slider(value: $facadeBearing, in: 0...359, step: 1)
        .tint(Color(red: 0.12, green: 0.43, blue: 0.89))

      HStack {
        Text("Nord")
        Spacer()
        Text("Ost")
        Spacer()
        Text("Süd")
        Spacer()
        Text("West")
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(Color.black.opacity(0.45))
    }
    .padding(16)
    .background(Palette.blueCard)
    .clipShape(PixBrand.tileShape())
    .overlay(PixBrand.tileShape().stroke(Color.black.opacity(0.06), lineWidth: 1))
    .environment(\.colorScheme, .light)
  }

  private var emptyStateCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Noch kein Objekt gewählt")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.82))
      Text("Gib oben eine Adresse ein oder übernimm die aktuelle Job-Adresse. Danach zeigt die App Sonnenaufgang, Sonnenuntergang, den Tagesbogen und die optimale Uhrzeit auf einem Satellitenbild.")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.6))
      if !suggestedAddress.isEmpty {
        Button {
          viewModel.query = SunPlanViewModel.primaryAddressLine(from: suggestedAddress)
          let suggestedLocality = SunPlanViewModel.secondaryAddressLine(from: suggestedAddress)
          if !suggestedLocality.isEmpty {
            viewModel.localityHint = suggestedLocality
          }
          Task { await runGeocode() }
        } label: {
          Label("Job-Adresse verwenden", systemImage: "building.2.crop.circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.76))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(PixBrand.tileShape())
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(Palette.pinkCard)
    .clipShape(PixBrand.tileShape())
    .overlay(
      PixBrand.tileShape()
        .stroke(Color.black.opacity(0.06), lineWidth: 1)
    )
    .environment(\.colorScheme, .light)
  }

  private func runGeocode() async {
    dismissKeyboard()
    await viewModel.search()
    persistLocation()
  }

  private func persistLocation() {
    storedQuery = viewModel.query
    storedLocalityHint = viewModel.localityHint
    if let coordinate = viewModel.coordinate {
      storedHasCoordinate = true
      storedLatitude = coordinate.latitude
      storedLongitude = coordinate.longitude
    } else {
      storedHasCoordinate = false
    }
  }

  private func moveMap(to coordinate: CLLocationCoordinate2D, animated: Bool = true) {
    let update = {
      mapPosition = .region(
        MKCoordinateRegion(
          center: coordinate,
          latitudinalMeters: mapVisibleMeters,
          longitudinalMeters: mapVisibleMeters
        )
      )
    }
    if animated {
      withAnimation(.easeInOut(duration: 0.35), update)
    } else {
      update()
    }
  }

  private func syncSelectedMinute() {
    guard let solarDay else { return }
    let now = Date()
    let nowComponents = Calendar.current.dateComponents([.hour, .minute], from: now)
    let currentMinute = Double((nowComponents.hour ?? 12) * 60 + (nowComponents.minute ?? 0))

    if selectedMinute < solarDay.sunriseMinute || selectedMinute > solarDay.sunsetMinute {
      selectedMinute = min(max(currentMinute, solarDay.sunriseMinute), solarDay.sunsetMinute)
      return
    }
    if selectedMinute < 0 {
      selectedMinute = min(max(currentMinute, solarDay.sunriseMinute), solarDay.sunsetMinute)
    }
  }

  private func timeString(forMinute minute: Double) -> String {
    let totalMinutes = Int(minute.rounded())
    let hours = max(0, totalMinutes / 60)
    let minutes = max(0, totalMinutes % 60)
    return String(format: "%02d:%02d", hours, minutes)
  }

  private func normalizedBearing(_ value: Double) -> Double {
    var normalized = value.truncatingRemainder(dividingBy: 360)
    if normalized < 0 {
      normalized += 360
    }
    return normalized
  }

  private func dismissKeyboard() {
    focusedField = nil
  }

  private func compassLabel(for bearing: Double) -> String {
    let directions = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
    let index = Int((normalizedBearing(bearing) + 22.5) / 45.0) % directions.count
    return directions[index]
  }

  private func badge(title: String, value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.82))
      Text(value)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(tint.opacity(0.88))
    .clipShape(PixBrand.tileShape())
  }

  private func mapZoomButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(Color.black.opacity(0.76))
        .frame(width: 34, height: 34)
        .background(Color.white.opacity(0.92))
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(systemName == "plus" ? "Karte vergrößern" : "Karte verkleinern")
  }

  private func infoTile(title: String, value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.46))
      Text(value)
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.white.opacity(0.78))
    .clipShape(PixBrand.tileShape())
  }

  private func sunMetricTile(title: String, value: String, symbol: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(tint)
        Text(title)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Palette.onLightSecondary)
      }

      Text(value)
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(Palette.onLightPrimary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.white.opacity(0.82))
    .clipShape(PixBrand.tileShape())
  }
}

@MainActor
private final class SunPlanViewModel: ObservableObject {
  @Published var query: String = ""
  @Published var localityHint: String = ""
  @Published var resolvedPlaceName: String?
  @Published var coordinate: CLLocationCoordinate2D?
  @Published var isSearching = false
  @Published var errorMessage: String?

  private var geocoder: CLGeocoder?

  func restore(query: String, localityHint: String, coordinate: CLLocationCoordinate2D?) {
    if self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      self.query = query
    }
    if self.localityHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      self.localityHint = localityHint
    }
    self.coordinate = coordinate
  }

  func search() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedLocalityHint = localityHint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Bitte eine Adresse eingeben."
      coordinate = nil
      resolvedPlaceName = nil
      return
    }

    geocoder?.cancelGeocode()
    isSearching = true
    errorMessage = nil
    let addressQuery = combinedAddressQuery(address: trimmed, localityHint: trimmedLocalityHint)
    let requestGeocoder = CLGeocoder()
    geocoder = requestGeocoder

    do {
      let placemarks = try await geocodeAddress(
        addressQuery,
        near: coordinate,
        geocoder: requestGeocoder
      )
      guard requestGeocoder === geocoder || geocoder == nil else {
        isSearching = false
        return
      }
      guard let place = placemarks.first,
            let placeCoordinate = place.location?.coordinate else {
        errorMessage = "Die Adresse konnte nicht aufgelöst werden."
        coordinate = nil
        resolvedPlaceName = nil
        isSearching = false
        geocoder = nil
        return
      }

      coordinate = placeCoordinate
      resolvedPlaceName = SunPlanViewModel.displayName(for: place) ?? addressQuery
      query = trimmed
      localityHint = trimmedLocalityHint.isEmpty
        ? (SunPlanViewModel.localityHint(for: place) ?? "")
        : trimmedLocalityHint
    } catch {
      if !SunPlanViewModel.isGeocodeCancellation(error) {
        errorMessage = "Die Adresse konnte gerade nicht gefunden werden."
        coordinate = nil
        resolvedPlaceName = nil
      }
    }

    if requestGeocoder === geocoder {
      geocoder = nil
    }
    isSearching = false
  }

  private func combinedAddressQuery(address: String, localityHint: String) -> String {
    guard !localityHint.isEmpty else { return address }
    let normalizedAddress = address.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let normalizedHint = localityHint.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    if normalizedAddress.contains(normalizedHint) {
      return address
    }
    return "\(address), \(localityHint)"
  }

  private func geocodeAddress(
    _ address: String,
    near coordinate: CLLocationCoordinate2D?,
    geocoder: CLGeocoder
  ) async throws -> [CLPlacemark] {
    if let coordinate {
      let region = CLCircularRegion(
        center: coordinate,
        radius: 2_500,
        identifier: "sunplan.search.region"
      )
      return try await geocoder.geocodeAddressString(address, in: region, preferredLocale: .current)
    }
    return try await geocoder.geocodeAddressString(address, in: nil, preferredLocale: .current)
  }

  private static func isGeocodeCancellation(_ error: Error) -> Bool {
    if error is CancellationError {
      return true
    }
    let nsError = error as NSError
    return nsError.domain == kCLErrorDomain && nsError.code == CLError.Code.geocodeCanceled.rawValue
  }

  private static func displayName(for placemark: CLPlacemark) -> String? {
    let candidates = [
      placemark.name,
      primaryAddressLine(for: placemark),
      localityHint(for: placemark)
    ]

    var parts: [String] = []
    for candidate in candidates {
      let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !trimmed.isEmpty else { continue }
      if parts.contains(where: { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
        continue
      }
      parts.append(trimmed)
    }

    if parts.isEmpty,
       let fullAddress = fullAddressLine(for: placemark)?.trimmingCharacters(in: .whitespacesAndNewlines),
       !fullAddress.isEmpty {
      return fullAddress
    }

    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: ", ")
  }

  private static func localityHint(for placemark: CLPlacemark) -> String? {
    let cityParts = [
      placemark.postalCode,
      placemark.locality ?? placemark.subAdministrativeArea,
      placemark.administrativeArea
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if !cityParts.isEmpty {
      return cityParts.joined(separator: " ")
    }

    let candidates: [String?] = [
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
      placemark.country
    ]

    for candidate in candidates {
      let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !trimmed.isEmpty {
        return trimmed
      }
    }

    return nil
  }

  private static func primaryAddressLine(for placemark: CLPlacemark) -> String? {
    let streetParts = [placemark.thoroughfare, placemark.subThoroughfare]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if !streetParts.isEmpty {
      return streetParts.joined(separator: " ")
    }
    return placemark.name
  }

  private static func fullAddressLine(for placemark: CLPlacemark) -> String? {
    let parts = [
      primaryAddressLine(for: placemark),
      localityHint(for: placemark),
      placemark.country
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: ", ")
  }

  static func primaryAddressLine(from fullAddress: String) -> String {
    let trimmed = fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    let components = trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
    return components.first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? trimmed
  }

  static func secondaryAddressLine(from fullAddress: String) -> String {
    let trimmed = fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    let components = trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
    guard components.count > 1 else { return "" }
    return String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct SunMapMarker: Identifiable {
  enum Prominence {
    case compact
    case normal
    case highlight
  }

  let id: String
  let coordinate: CLLocationCoordinate2D
  let label: String
  let secondaryLabel: String
  let tint: Color
  let prominence: Prominence
}

private struct SunMapMarkerView: View {
  let marker: SunMapMarker

  var body: some View {
    VStack(spacing: 4) {
      if marker.prominence != .compact {
        VStack(spacing: 1) {
          Text(marker.label)
            .font(.system(size: marker.prominence == .highlight ? 11 : 10, weight: .semibold))
            .foregroundStyle(Color.white)
          Text(marker.secondaryLabel)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.84))
        }
        .padding(.horizontal, marker.prominence == .highlight ? 10 : 8)
        .padding(.vertical, marker.prominence == .highlight ? 7 : 6)
        .background(marker.tint.opacity(marker.prominence == .highlight ? 0.96 : 0.88))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 10, y: 3)
      }

      Circle()
        .fill(marker.tint)
        .frame(width: marker.prominence == .highlight ? 16 : 12, height: marker.prominence == .highlight ? 16 : 12)
        .overlay(
          Circle()
            .stroke(Color.white.opacity(0.88), lineWidth: 2)
        )
    }
  }
}

private struct SunLightAssessment {
  let title: String
  let subtitle: String
  let tint: Color
  let symbolName: String
}

private struct SunLightWindow {
  let startMinute: Double
  let endMinute: Double
  let title: String
  let reason: String
  let tint: Color

  var midpointMinute: Double {
    (startMinute + endMinute) / 2
  }
}

private struct SolarPosition {
  let date: Date
  let azimuthDegrees: Double
  let elevationDegrees: Double
}

private struct SolarDaySummary {
  let coordinate: CLLocationCoordinate2D
  let dayStart: Date
  let sunriseMinute: Double
  let solarNoonMinute: Double
  let sunsetMinute: Double
  let timeZone: TimeZone

  func date(atMinute minute: Double) -> Date {
    dayStart.addingTimeInterval(minute * 60)
  }

  func position(atMinute minute: Double) -> SolarPosition {
    SolarCalculator.position(
      for: date(atMinute: minute),
      coordinate: coordinate,
      timeZone: timeZone
    )
  }

  func pathCoordinates(maxRadiusMeters: Double) -> [CLLocationCoordinate2D] {
    let step = max(10.0, min(40.0, (sunsetMinute - sunriseMinute) / 14.0))
    let samples = stride(from: sunriseMinute, through: sunsetMinute, by: step).map { position(atMinute: $0) }
    let ensured = samples.last?.date != date(atMinute: sunsetMinute) ? samples + [position(atMinute: sunsetMinute)] : samples
    return ensured.map {
      SolarMapProjection.coordinate(
        from: coordinate,
        azimuthDegrees: $0.azimuthDegrees,
        elevationDegrees: $0.elevationDegrees,
        maxRadiusMeters: maxRadiusMeters
      )
    }
  }
}

private enum SolarMapProjection {
  static func coordinate(
    from origin: CLLocationCoordinate2D,
    azimuthDegrees: Double,
    elevationDegrees: Double,
    maxRadiusMeters: Double
  ) -> CLLocationCoordinate2D {
    let clampedElevation = min(max(elevationDegrees, 0), 75)
    let normalized = clampedElevation / 75.0
    let distance = maxRadiusMeters - (normalized * maxRadiusMeters * 0.46)
    return destinationCoordinate(
      from: origin,
      bearingDegrees: azimuthDegrees,
      distanceMeters: max(70, distance)
    )
  }

  static func destinationCoordinate(
    from origin: CLLocationCoordinate2D,
    bearingDegrees: Double,
    distanceMeters: Double
  ) -> CLLocationCoordinate2D {
    let earthRadius = 6_371_000.0
    let bearing = bearingDegrees * .pi / 180
    let latitude = origin.latitude * .pi / 180
    let longitude = origin.longitude * .pi / 180
    let angularDistance = distanceMeters / earthRadius

    let resultLatitude = asin(
      sin(latitude) * cos(angularDistance)
      + cos(latitude) * sin(angularDistance) * cos(bearing)
    )
    let resultLongitude = longitude + atan2(
      sin(bearing) * sin(angularDistance) * cos(latitude),
      cos(angularDistance) - sin(latitude) * sin(resultLatitude)
    )

    return CLLocationCoordinate2D(
      latitude: resultLatitude * 180 / .pi,
      longitude: resultLongitude * 180 / .pi
    )
  }
}

private enum SolarCalculator {
  static func makeDaySummary(
    for date: Date,
    coordinate: CLLocationCoordinate2D,
    timeZone: TimeZone
  ) -> SolarDaySummary? {
    let calendar = Calendar(identifier: .gregorian)
    let localDay = calendar.startOfDay(for: date)
    let midday = calendar.date(byAdding: .hour, value: 12, to: localDay) ?? date
    let tzHours = Double(timeZone.secondsFromGMT(for: midday)) / 3600.0

    let julian = julianDay(for: midday)
    let julianCentury = (julian - 2_451_545.0) / 36_525.0
    let solarDeclination = sunDeclination(julianCentury: julianCentury)
    let equation = equationOfTime(julianCentury: julianCentury)

    let latitudeRad = coordinate.latitude * .pi / 180
    let declinationRad = solarDeclination * .pi / 180
    let hourAngleInput =
      (cos(90.833 * .pi / 180) / (cos(latitudeRad) * cos(declinationRad)))
      - tan(latitudeRad) * tan(declinationRad)

    guard hourAngleInput.isFinite, hourAngleInput >= -1, hourAngleInput <= 1 else {
      return nil
    }

    let hourAngle = acos(hourAngleInput) * 180 / .pi
    let solarNoon = 720 - (4 * coordinate.longitude) - equation + (tzHours * 60)
    let sunrise = solarNoon - (hourAngle * 4)
    let sunset = solarNoon + (hourAngle * 4)

    return SolarDaySummary(
      coordinate: coordinate,
      dayStart: localDay,
      sunriseMinute: sunrise,
      solarNoonMinute: solarNoon,
      sunsetMinute: sunset,
      timeZone: timeZone
    )
  }

  static func position(
    for date: Date,
    coordinate: CLLocationCoordinate2D,
    timeZone: TimeZone
  ) -> SolarPosition {
    let julian = julianDay(for: date)
    let julianCentury = (julian - 2_451_545.0) / 36_525.0
    let equation = equationOfTime(julianCentury: julianCentury)
    let declination = sunDeclination(julianCentury: julianCentury)

    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents(in: timeZone, from: date)
    let minuteOfDay =
      Double((components.hour ?? 0) * 60)
      + Double(components.minute ?? 0)
      + Double(components.second ?? 0) / 60.0
    let offsetHours = Double(timeZone.secondsFromGMT(for: date)) / 3600.0

    var trueSolarTime = minuteOfDay + equation + (4 * coordinate.longitude) - (60 * offsetHours)
    trueSolarTime.formTruncatingRemainder(dividingBy: 1440)
    if trueSolarTime < 0 {
      trueSolarTime += 1440
    }

    let hourAngle = (trueSolarTime / 4.0 < 0)
      ? (trueSolarTime / 4.0) + 180
      : (trueSolarTime / 4.0) - 180

    let latitudeRad = coordinate.latitude * .pi / 180
    let declinationRad = declination * .pi / 180
    let hourAngleRad = hourAngle * .pi / 180

    let cosineZenith =
      sin(latitudeRad) * sin(declinationRad)
      + cos(latitudeRad) * cos(declinationRad) * cos(hourAngleRad)
    let zenith = acos(min(max(cosineZenith, -1), 1)) * 180 / .pi
    let elevation = 90 - zenith

    let azimuthDenominator = cos(latitudeRad) * sin(zenith * .pi / 180)
    let azimuth: Double
    if abs(azimuthDenominator) > 0.001 {
      let azimuthNumerator =
        (sin(latitudeRad) * cos(zenith * .pi / 180))
        - sin(declinationRad)
      var raw = acos(
        min(max(azimuthNumerator / azimuthDenominator, -1), 1)
      ) * 180 / .pi
      if hourAngle > 0 {
        raw = (raw + 180).truncatingRemainder(dividingBy: 360)
      } else {
        raw = (540 - raw).truncatingRemainder(dividingBy: 360)
      }
      azimuth = raw
    } else {
      azimuth = coordinate.latitude > 0 ? 180 : 0
    }

    return SolarPosition(
      date: date,
      azimuthDegrees: azimuth,
      elevationDegrees: elevation
    )
  }

  static func assessment(
    for position: SolarPosition,
    facadeBearing: Double
  ) -> SunLightAssessment {
    if position.elevationDegrees <= 0 {
      return SunLightAssessment(
        title: "Sonne unter dem Horizont",
        subtitle: "Zu dieser Uhrzeit gibt es kein direktes Sonnenlicht am Objekt.",
        tint: Color.gray.opacity(0.75),
        symbolName: "moon.stars.fill"
      )
    }

    let difference = angularDifference(position.azimuthDegrees, facadeBearing)
    if difference < 35 {
      if position.elevationDegrees < 12 {
        return SunLightAssessment(
          title: "Flaches Frontlicht",
          subtitle: "Die Sonne steht niedrig und kommt fast direkt auf die gewählte Objektseite.",
          tint: Color.orange,
          symbolName: "sunrise.fill"
        )
      }
      if position.elevationDegrees < 52 {
        return SunLightAssessment(
          title: "Front gut beleuchtet",
          subtitle: "Die Sonne trifft die gewählte Objektseite direkt. Das ist oft ein sehr guter Aufnahmezeitpunkt.",
          tint: Color.green.opacity(0.82),
          symbolName: "sun.max.fill"
        )
      }
      return SunLightAssessment(
        title: "Viel Licht, aber steil",
        subtitle: "Die Objektseite bekommt Licht, die Sonne steht aber bereits ziemlich hoch.",
        tint: Color.yellow.opacity(0.88),
        symbolName: "sun.max.trianglebadge.exclamationmark"
      )
    }

    if difference < 75 {
      return SunLightAssessment(
        title: "Seitliches Licht",
        subtitle: "Die Sonne kommt seitlich. Das kann gut wirken, wenn du mehr Struktur und Schatten willst.",
        tint: Color.blue.opacity(0.82),
        symbolName: "sun.haze.fill"
      )
    }

    if difference < 115 {
      return SunLightAssessment(
        title: "Querlicht",
        subtitle: "Die Sonne steht seitlich bis rückwärtig. Prüfe auf harte Schatten oder dunklere Fassadenflächen.",
        tint: Color.orange.opacity(0.88),
        symbolName: "sun.dust.fill"
      )
    }

    return SunLightAssessment(
      title: "Eher Gegenlicht",
      subtitle: "Die Sonne steht hinter dem Objekt. Für diese Seite ist meist ein anderer Zeitpunkt besser.",
      tint: Color.red.opacity(0.82),
      symbolName: "sun.max.circle.fill"
    )
  }

  static func bestWindow(
    for day: SolarDaySummary,
    facadeBearing: Double
  ) -> SunLightWindow? {
    let minutes = stride(from: max(day.sunriseMinute, 0), through: min(day.sunsetMinute, 24 * 60), by: 15.0).map { $0 }
    guard !minutes.isEmpty else { return nil }

    let scored: [(minute: Double, score: Double, position: SolarPosition)] = minutes.map { minute in
      let position = day.position(atMinute: minute)
      let score = sunlightScore(position: position, facadeBearing: facadeBearing)
      return (minute, score, position)
    }

    guard let bestScore = scored.map(\.score).max(), bestScore > 0.16 else {
      return nil
    }

    let threshold = max(0.42, bestScore * 0.82)
    var bestRange: (start: Double, end: Double, average: Double)?
    var currentStart: Double?
    var currentScores: [Double] = []

    for entry in scored {
      if entry.score >= threshold {
        if currentStart == nil {
          currentStart = entry.minute
        }
        currentScores.append(entry.score)
      } else if let activeStart = currentStart {
        let average = currentScores.reduce(0, +) / Double(max(currentScores.count, 1))
        let candidate = (start: activeStart, end: entry.minute, average: average)
        if bestRange == nil || candidate.average > bestRange!.average {
          bestRange = candidate
        }
        self.resetRange(&currentStart, &currentScores)
      }
    }

    if let activeStart = currentStart {
      let average = currentScores.reduce(0, +) / Double(max(currentScores.count, 1))
      let candidate = (start: activeStart, end: scored.last?.minute ?? activeStart, average: average)
      if bestRange == nil || candidate.average > bestRange!.average {
        bestRange = candidate
      }
    }

    guard let bestRange else { return nil }
    let midpoint = (bestRange.start + bestRange.end) / 2
    let midpointPosition = day.position(atMinute: midpoint)
    let difference = angularDifference(midpointPosition.azimuthDegrees, facadeBearing)

    if difference < 35 {
      return SunLightWindow(
        startMinute: bestRange.start,
        endMinute: bestRange.end,
        title: "Eher diese Zeit anpeilen",
        reason: "Die Sonne beleuchtet die gewählte Objektseite in diesem Fenster am direktesten.",
        tint: Color.green.opacity(0.82)
      )
    }

    if midpoint < day.solarNoonMinute {
      return SunLightWindow(
        startMinute: bestRange.start,
        endMinute: bestRange.end,
        title: "Vormittag ist heute besser",
        reason: "Vor dem Sonnenhöchststand liegt die Sonne günstiger auf deiner gewählten Objektseite.",
        tint: Color.orange.opacity(0.9)
      )
    }

    return SunLightWindow(
      startMinute: bestRange.start,
      endMinute: bestRange.end,
      title: "Nachmittag ist heute besser",
      reason: "Nach dem Sonnenhöchststand passt die Richtung besser zur gewählten Objektseite.",
      tint: Color.blue.opacity(0.82)
    )
  }

  private static func sunlightScore(position: SolarPosition, facadeBearing: Double) -> Double {
    guard position.elevationDegrees > 4 else { return 0 }
    let angleDifference = angularDifference(position.azimuthDegrees, facadeBearing)
    let directionScore = max(0, 1 - (angleDifference / 120))
    let preferredElevation = 26.0
    let elevationScore = max(0, 1 - abs(position.elevationDegrees - preferredElevation) / 32.0)
    let steepPenalty = position.elevationDegrees > 58 ? 0.84 : 1.0
    return ((directionScore * 0.72) + (elevationScore * 0.28)) * steepPenalty
  }

  private static func angularDifference(_ left: Double, _ right: Double) -> Double {
    let raw = abs(left - right).truncatingRemainder(dividingBy: 360)
    return min(raw, 360 - raw)
  }

  private static func resetRange(_ start: inout Double?, _ scores: inout [Double]) {
    start = nil
    scores.removeAll(keepingCapacity: true)
  }

  private static func julianDay(for date: Date) -> Double {
    (date.timeIntervalSince1970 / 86_400.0) + 2_440_587.5
  }

  private static func equationOfTime(julianCentury: Double) -> Double {
    let epsilon = obliquityCorrection(julianCentury: julianCentury)
    let l0 = geometricMeanLongitude(julianCentury: julianCentury) * .pi / 180
    let eccentricity = eccentricityEarthOrbit(julianCentury: julianCentury)
    let anomaly = geometricMeanAnomaly(julianCentury: julianCentury) * .pi / 180
    let y = tan((epsilon * .pi / 180) / 2)
    let ySquared = y * y

    let equation =
      ySquared * sin(2 * l0)
      - 2 * eccentricity * sin(anomaly)
      + 4 * eccentricity * ySquared * sin(anomaly) * cos(2 * l0)
      - 0.5 * ySquared * ySquared * sin(4 * l0)
      - 1.25 * eccentricity * eccentricity * sin(2 * anomaly)

    return 4 * equation * 180 / .pi
  }

  private static func sunDeclination(julianCentury: Double) -> Double {
    let epsilon = obliquityCorrection(julianCentury: julianCentury)
    let lambda = sunApparentLongitude(julianCentury: julianCentury)
    let sint = sin(epsilon * .pi / 180) * sin(lambda * .pi / 180)
    return asin(sint) * 180 / .pi
  }

  private static func geometricMeanLongitude(julianCentury: Double) -> Double {
    var value = 280.46646 + julianCentury * (36_000.76983 + julianCentury * 0.0003032)
    value.formTruncatingRemainder(dividingBy: 360)
    if value < 0 {
      value += 360
    }
    return value
  }

  private static func geometricMeanAnomaly(julianCentury: Double) -> Double {
    357.52911 + julianCentury * (35_999.05029 - 0.0001537 * julianCentury)
  }

  private static func eccentricityEarthOrbit(julianCentury: Double) -> Double {
    0.016708634 - julianCentury * (0.000042037 + 0.0000001267 * julianCentury)
  }

  private static func sunEquationOfCenter(julianCentury: Double) -> Double {
    let anomaly = geometricMeanAnomaly(julianCentury: julianCentury) * .pi / 180
    return sin(anomaly) * (1.914602 - julianCentury * (0.004817 + 0.000014 * julianCentury))
      + sin(2 * anomaly) * (0.019993 - 0.000101 * julianCentury)
      + sin(3 * anomaly) * 0.000289
  }

  private static func sunTrueLongitude(julianCentury: Double) -> Double {
    geometricMeanLongitude(julianCentury: julianCentury) + sunEquationOfCenter(julianCentury: julianCentury)
  }

  private static func sunApparentLongitude(julianCentury: Double) -> Double {
    let omega = 125.04 - 1934.136 * julianCentury
    return sunTrueLongitude(julianCentury: julianCentury) - 0.00569 - 0.00478 * sin(omega * .pi / 180)
  }

  private static func meanObliquityOfEcliptic(julianCentury: Double) -> Double {
    let seconds = 21.448 - julianCentury * (46.8150 + julianCentury * (0.00059 - julianCentury * 0.001813))
    return 23 + (26 + (seconds / 60)) / 60
  }

  private static func obliquityCorrection(julianCentury: Double) -> Double {
    let omega = 125.04 - 1934.136 * julianCentury
    return meanObliquityOfEcliptic(julianCentury: julianCentury) + 0.00256 * cos(omega * .pi / 180)
  }
}
