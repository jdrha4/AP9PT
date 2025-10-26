import SwiftUI

enum AppTab {
    case home
    case search
}

struct ContentView: View {
    @State private var currentTab: AppTab = .home
    @State private var dragOffset: CGFloat = 0 // live horizontal drag offset
    @State private var isHorizontalDrag: Bool = false // lock once we detect horizontal intent
    @State private var isKeyboardVisible: Bool = false
    
    // Swipe configuration
    private let swipeThresholdRatio: CGFloat = 0.25 // percent of width required to commit
    private let horizontalLockHysteresis: CGFloat = 6 // extra pixels beyond vertical before locking
    
    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1) // avoid division by zero
            
            // The horizontal drag gesture used for tab preview/switching
            let horizontalDrag = DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    // If the keyboard is up, do not engage horizontal at all — let vertical and text fields win.
                    if isKeyboardVisible {
                        return
                    }
                    
                    let dx = value.translation.width
                    let dy = value.translation.height
                    
                    if !isHorizontalDrag {
                        // Decide if we should lock into horizontal drag
                        if abs(dx) > abs(dy) + horizontalLockHysteresis {
                            isHorizontalDrag = true
                        } else {
                            // Not locked yet; do not interfere with vertical scroll
                            return
                        }
                    }
                    
                    // Once locked, only allow dragging toward an available neighbor:
                    // - From Home, only allow left swipes (to Search).
                    // - From Search, only allow right swipes (to Home).
                    switch currentTab {
                    case .home:
                        dragOffset = min(0, dx) // clamp to <= 0 (left only)
                    case .search:
                        dragOffset = max(0, dx) // clamp to >= 0 (right only)
                    }
                }
                .onEnded { value in
                    // If we never locked horizontally (e.g., keyboard visible or purely vertical), nothing to do.
                    defer {
                        isHorizontalDrag = false
                        dragOffset = 0
                    }
                    
                    let dx = value.translation.width
                    let shouldGoToSearch = (currentTab == .home && dx < 0 && abs(dx) > width * swipeThresholdRatio)
                    let shouldGoToHome   = (currentTab == .search && dx > 0 && abs(dx) > width * swipeThresholdRatio)
                    
                    if shouldGoToSearch {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentTab = .search
                        }
                    } else if shouldGoToHome {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentTab = .home
                        }
                    } else {
                        // Not far enough: cancel and spring back
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            // dragOffset reset happens in defer
                        }
                    }
                }
            
            ZStack {
                // Both views are always in the hierarchy; we position them with offsets.
                HomeView(scrollDisabled: !isKeyboardVisible) // disable vertical by default; enable when keyboard is visible
                    .offset(x: homeOffset(width: width))
                    .allowsHitTesting(currentTab == .home && dragOffset == 0)
                    .accessibilityHidden(currentTab != .home && dragOffset == 0)
                
                SearchView(scrollDisabled: !isKeyboardVisible) // disable vertical by default; enable when keyboard is visible
                    .offset(x: searchOffset(width: width))
                    .allowsHitTesting(currentTab == .search && dragOffset == 0)
                    .accessibilityHidden(currentTab != .search && dragOffset == 0)
            }
            // Only animate the committed tab change, not the live drag
            .animation(.easeInOut(duration: 0.28), value: currentTab)
            .contentShape(Rectangle()) // allow hits across the whole area
            // Attach the horizontal gesture simultaneously and only to this container's gesture arena.
            // This ensures subviews (TextField, Buttons) receive taps immediately.
            .modifier(HGestureChooser(isKeyboardVisible: isKeyboardVisible, gesture: horizontalDrag))
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.blue, .purple]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .safeAreaInset(edge: .bottom) {
                BottomBar(
                    currentTab: $currentTab,
                    onSelect: { target in
                        guard target != currentTab else { return }
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentTab = target
                        }
                    }
                )
                .frame(height: 50)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        // Track keyboard visibility to switch gesture behavior
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
            // If user brings up the keyboard mid-gesture, ensure we stop any horizontal lock.
            isHorizontalDrag = false
            dragOffset = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }
    
    // MARK: - Offsets
    
    private func homeOffset(width: CGFloat) -> CGFloat {
        // Base positions when idle:
        // - If current is home: home at 0, search at +width.
        // - If current is search: home at -width, search at 0.
        switch currentTab {
        case .home:
            // While dragging left, home tracks the finger to the left.
            return dragOffset // dragOffset <= 0
        case .search:
            // While dragging right (to return), home starts at -width and comes in with drag.
            return -width + max(0, dragOffset)
        }
    }
    
    private func searchOffset(width: CGFloat) -> CGFloat {
        switch currentTab {
        case .home:
            // Search starts off-screen right at +width and comes in with left drag.
            return width + min(0, dragOffset)
        case .search:
            // When current is search, it sits at 0 and can be dragged right.
            return dragOffset // dragOffset >= 0
        }
    }
}

private struct HGestureChooser<G: Gesture>: ViewModifier {
    let isKeyboardVisible: Bool
    let gesture: G
    
    func body(content: Content) -> some View {
        // Always attach simultaneously and only to this view's own gesture arena.
        // This prevents delaying or preempting taps inside subviews (like TextField).
        content.simultaneousGesture(gesture, including: .gesture)
    }
}

private struct BottomBar: View {
    @Binding var currentTab: AppTab
    var onSelect: (AppTab) -> Void
    
    var body: some View {
        HStack(spacing: 24) {
            Button {
                onSelect(.home)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Home")
                        .font(.footnote)
                }
                .foregroundColor(currentTab == .home ? .white : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            
            Button {
                onSelect(.search)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Search")
                        .font(.footnote)
                }
                .foregroundColor(currentTab == .search ? .white : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Home Screen

private struct HomeView: View {
    @StateObject private var viewModel = ViewModel()
    @AppStorage("savedCity") private var savedCity: String = "jabalpur"
    @State private var tempCity: String = "" // staging text for saving
    
    // For suggestions on Home like Search
    @FocusState private var changeFocused: Bool
    @State private var suppressSearch: Bool = false
    
    // Accept whether vertical scroll should be disabled while horizontally dragging
    let scrollDisabled: Bool
    
    // Layout constants (reuse from Search for consistent sizing)
    private let fieldBottomPadding: CGFloat = 8
    private let fieldEstimatedHeight: CGFloat = 44
    private let fieldMaxWidth: CGFloat = 520
    
    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    Text("Home")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white.gradient)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 16)
                    
                    // Saved city card
                    VStack(spacing: 12) {
                        Text("Default City")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text(savedCity)
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.white)
                        
                        // Editable field + save
                        VStack(spacing: 0) {
                            HStack {
                                TextField("Change city", text: $tempCity)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .padding(.horizontal)
                                    .frame(maxWidth: fieldMaxWidth)
                                    .focused($changeFocused)
                                    .submitLabel(.done)
                                    .onTapGesture { changeFocused = true }
                                    .onSubmit {
                                        changeFocused = false
                                        viewModel.cancelSuggestions()
                                        let trimmed = tempCity.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty {
                                            savedCity = trimmed
                                            viewModel.fetch(city: savedCity)
                                            tempCity = ""
                                        }
                                    }
                                    .onChange(of: tempCity) { newValue in
                                        let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !suppressSearch {
                                            viewModel.searchCities(query: q)
                                        }
                                    }
                                
                                Button("Save") {
                                    changeFocused = false
                                    viewModel.cancelSuggestions()
                                    let trimmed = tempCity.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        savedCity = trimmed
                                        viewModel.fetch(city: savedCity)
                                        tempCity = ""
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, fieldBottomPadding)
                        }
                        .padding(.horizontal)
                        .overlay(alignment: .top) {
                            if !viewModel.suggestions.isEmpty {
                                SuggestionsList(
                                    suggestions: viewModel.suggestions,
                                    onSelect: { suggestion in
                                        suppressSearch = true
                                        changeFocused = false
                                        viewModel.cancelSuggestions()
                                        
                                        let displayName = formattedName(for: suggestion)
                                        // Persist the chosen city name and fetch by coordinates
                                        savedCity = displayName
                                        viewModel.selectSuggestion(suggestion)
                                        tempCity = ""
                                        
                                        DispatchQueue.main.async {
                                            suppressSearch = false
                                        }
                                    }
                                )
                                .frame(maxWidth: fieldMaxWidth)
                                .padding(.top, fieldEstimatedHeight + fieldBottomPadding + 6)
                                .padding(.horizontal)
                                .zIndex(1)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .animation(.easeInOut(duration: 0.2), value: viewModel.suggestions)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: 520)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    
                    // Weather for saved city
                    if let weather = viewModel.apidata {
                        let iconCode = weather.weather.first?.icon ?? "01d"
                        Image(systemName: sfSymbolName(for: iconCode))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .font(.system(size: 140, weight: .regular))
                            .padding(.bottom, 8)
                        
                        Text("\(weather.main.temp, specifier: "%.1f")°C")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(weather.name)
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Text("Humidity: \(weather.main.humidity) %")
                            .foregroundColor(.white.opacity(0.9))
                        Text("Feels like: \(weather.main.feels_like, specifier: "%.1f")°C")
                            .foregroundColor(.white.opacity(0.9))
                        Text("Wind: \(weather.wind.speed * 3.6, specifier: "%.2f") km/h")
                            .foregroundColor(.white.opacity(0.9))
                        Text("Condition: \(weather.weather[0].description)")
                            .foregroundColor(.white.opacity(0.9))
                    } else {
                        Text("Set your default city above to see its weather here.")
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.top, 8)
                    }
                    
                    Spacer(minLength: 40)
                }
                .frame(minHeight: geo.size.height + 1, alignment: .top)
            }
            .scrollDisabled(scrollDisabled)
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onAppear {
                // Always load the saved city at app start
                viewModel.fetch(city: savedCity)
            }
        }
    }
    
    private func formattedName(for s: GeoLocation) -> String {
        if let state = s.state, !state.isEmpty {
            return "\(s.name), \(s.state), \(s.country)"
        } else {
            return "\(s.name), \(s.country)"
        }
    }
    
    private func sfSymbolName(for icon: String) -> String {
        switch icon {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.stars.fill"
        case "02d": return "cloud.sun.fill"
        case "02n": return "cloud.moon.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "smoke.fill"
        case "09d", "09n": return "cloud.drizzle.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.rain.fill"
        case "13d", "13n": return "cloud.snow.fill"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - Search Screen

private struct SearchView: View {
    @StateObject private var viewModel = ViewModel()
    @State private var city: String = ""
    @FocusState private var searchFocused: Bool
    @State private var suppressSearch: Bool = false
    
    // Layout constants
    private let fieldBottomPadding: CGFloat = 8
    private let fieldEstimatedHeight: CGFloat = 44
    private let fieldMaxWidth: CGFloat = 520
    
    // Accept whether vertical scroll should be disabled while horizontally dragging
    let scrollDisabled: Bool
    
    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    VStack {
                        Text("Search")
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(.white.gradient)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
                            .padding(.vertical)
                        
                        VStack(spacing: 0) {
                            HStack {
                                TextField("Enter city name", text: $city)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .padding(.horizontal)
                                    .frame(maxWidth: fieldMaxWidth)
                                    .focused($searchFocused)
                                    .submitLabel(.search)
                                    .onTapGesture { searchFocused = true }
                                    .onSubmit {
                                        searchFocused = false
                                        viewModel.cancelSuggestions()
                                        viewModel.fetch(city: city.isEmpty ? "jabalpur" : city)
                                    }
                                    .onChange(of: city) { newValue in
                                        // Trigger suggestions on any edit; ViewModel handles <2 chars by clearing
                                        let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !suppressSearch {
                                            viewModel.searchCities(query: q)
                                        }
                                    }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, fieldBottomPadding)
                        }
                        .padding(.horizontal)
                        .overlay(alignment: .top) {
                            if !viewModel.suggestions.isEmpty {
                                SuggestionsList(
                                    suggestions: viewModel.suggestions,
                                    onSelect: { suggestion in
                                        suppressSearch = true
                                        searchFocused = false
                                        viewModel.cancelSuggestions()
                                        
                                        let displayName = formattedName(for: suggestion)
                                        city = displayName
                                        viewModel.selectSuggestion(suggestion)
                                        
                                        DispatchQueue.main.async {
                                            suppressSearch = false
                                        }
                                    }
                                )
                                .frame(maxWidth: fieldMaxWidth)
                                .padding(.top, fieldEstimatedHeight + fieldBottomPadding + 6)
                                .padding(.horizontal)
                                .zIndex(1)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .animation(.easeInOut(duration: 0.2), value: viewModel.suggestions)
                            }
                        }
                        .zIndex(1)
                        
                        if let weather = viewModel.apidata {
                            let iconCode = weather.weather.first?.icon ?? "01d"
                            Image(systemName: sfSymbolName(for: iconCode))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white)
                                .font(.system(size: 160, weight: .regular))
                                .padding(.bottom, 8)
                            
                            Text("\(weather.main.temp, specifier: "%.1f")°C")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                            
                            Text(weather.name)
                                .font(.title)
                                .foregroundColor(.white)
                            
                            Text("Humidity: \(weather.main.humidity) %")
                                .foregroundColor(.white)
                            
                            Text("Feels like: \(weather.main.feels_like, specifier: "%.1f")°C")
                                .foregroundColor(.white)
                            
                            Text("Wind speed: \(weather.wind.speed * 3.6, specifier: "%.2f") km/h")
                                .foregroundColor(.white)
                            
                            Text("Condition: \(weather.weather[0].description)")
                                .foregroundColor(.white)
                        } else {
                            Text("Welcome to Weather App")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding(.bottom, 20)
                        }
                    }
                    .padding(.bottom, 100)
                }
                .frame(minHeight: geo.size.height + 1, alignment: .top)
            }
            .scrollDisabled(scrollDisabled)
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.blue, .purple]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .onAppear {
                if viewModel.apidata == nil {
                    viewModel.fetch(city: "jabalpur")
                }
            }
        }
    }
    
    private func formattedName(for s: GeoLocation) -> String {
        if let state = s.state, !state.isEmpty {
            return "\(s.name), \(s.state), \(s.country)"
        } else {
            return "\(s.name), \(s.country)"
        }
    }
    
    private func sfSymbolName(for icon: String) -> String {
        switch icon {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.stars.fill"
        case "02d": return "cloud.sun.fill"
        case "02n": return "cloud.moon.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "smoke.fill"
        case "09d", "09n": return "cloud.drizzle.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.rain.fill"
        case "13d", "13n": return "cloud.snow.fill"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - Suggestions UI (shared)

private struct SuggestionsList: View {
    let suggestions: [GeoLocation]
    let onSelect: (GeoLocation) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.blue)
                        Text(formattedName(for: suggestion))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                
                if suggestion.id != suggestions.last?.id {
                    Divider()
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("SuggestionsList")
    }
    
    private func formattedName(for s: GeoLocation) -> String {
        if let state = s.state, !state.isEmpty {
            return "\(s.name), \(s.state), \(s.country)"
        } else {
            return "\(s.name), \(s.country)"
        }
    }
}

#Preview {
    ContentView()
}
