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
    @State private var isShowingSettings: Bool = false
    
    // Swipe configuration
    private let swipeThresholdRatio: CGFloat = 0.25 // percent of width required to commit
    private let horizontalLockHysteresis: CGFloat = 6 // extra pixels beyond vertical before locking
    
    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1) // avoid division by zero
            
            // The horizontal drag gesture used for tab preview/switching
            let horizontalDrag = DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    // If the keyboard is up, or settings overlay is visible, do not engage horizontal at all.
                    if isKeyboardVisible || isShowingSettings { return }
                    
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
                    
                    // Once locked, only allow dragging toward an available neighbor (Home <-> Search).
                    switch currentTab {
                    case .home:
                        dragOffset = min(0, dx) // clamp to <= 0 (left only)
                    case .search:
                        dragOffset = max(0, dx) // clamp to >= 0 (right only)
                    }
                }
                .onEnded { value in
                    // If we never locked horizontally (e.g., keyboard visible or purely vertical), nothing to do.
                    if !isHorizontalDrag || isShowingSettings {
                        dragOffset = 0
                        return
                    }
                    
                    let oldDrag = dragOffset
                    let dx = value.translation.width
                    let passedThreshold = abs(dx) > width * swipeThresholdRatio || abs(oldDrag) > width * swipeThresholdRatio
                    
                    // Reset lock now; we'll animate dragOffset as needed below.
                    isHorizontalDrag = false
                    
                    switch currentTab {
                    case .home:
                        if passedThreshold && dx < 0 {
                            // Commit to Search while preserving visual continuity.
                            // Under .home, searchOffset = width + oldDrag.
                            let currentSearchOffset = width + oldDrag
                            
                            withAnimation(nil) {
                                currentTab = .search
                                // Under .search, searchOffset = dragOffset; keep the same on-screen position.
                                dragOffset = currentSearchOffset
                            }
                            withAnimation(.easeInOut(duration: 0.28)) {
                                dragOffset = 0
                            }
                        } else {
                            // Cancel
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                dragOffset = 0
                            }
                        }
                        
                    case .search:
                        if passedThreshold && dx > 0 {
                            // Commit to Home while preserving visual continuity.
                            // Under .search, homeOffset = -width + oldDrag.
                            let currentHomeOffset = -width + oldDrag
                            
                            withAnimation(nil) {
                                currentTab = .home
                                // Under .home, homeOffset = dragOffset; keep the same on-screen position.
                                dragOffset = currentHomeOffset
                            }
                            withAnimation(.easeInOut(duration: 0.28)) {
                                dragOffset = 0
                            }
                        } else {
                            // Cancel
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                dragOffset = 0
                            }
                        }
                    }
                }
            
            ZStack {
                // Base tabs stack (Home and Search)
                ZStack {
                    // Home (simple)
                    SimpleHomeView(onTapSettings: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isShowingSettings = true
                            dragOffset = 0
                        }
                    }, scrollDisabled: !isKeyboardVisible)
                    .offset(x: homeOffset(width: width))
                    .allowsHitTesting(!isShowingSettings && currentTab == .home && dragOffset == 0)
                    .accessibilityHidden(currentTab != .home && dragOffset == 0)
                    
                    // Search (unchanged except city name placement above icon)
                    SearchView(scrollDisabled: !isKeyboardVisible)
                        .offset(x: searchOffset(width: width))
                        .allowsHitTesting(!isShowingSettings && currentTab == .search && dragOffset == 0)
                        .accessibilityHidden(currentTab != .search && dragOffset == 0)
                }
                // Settings overlay fades above the Home tab
                if isShowingSettings {
                    SettingsView(onDismiss: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isShowingSettings = false
                        }
                    })
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            // We control animations manually; do not implicitly animate on currentTab changes.
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
                        // Button taps should still animate a full switch.
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentTab = target
                            dragOffset = 0
                        }
                    }
                )
                .frame(height: 50)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(!isShowingSettings) // prevent taps while settings overlay is up
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
    
    // MARK: - Offsets (Home <-> Search only)
    
    private func homeOffset(width: CGFloat) -> CGFloat {
        switch currentTab {
        case .home:
            return dragOffset // <= 0 when dragging left
        case .search:
            return -width + max(0, dragOffset) // comes in when dragging right
        }
    }
    
    private func searchOffset(width: CGFloat) -> CGFloat {
        switch currentTab {
        case .home:
            return width + min(0, dragOffset) // starts at +width, comes in when dragging left
        case .search:
            return dragOffset // >= 0 when dragging right to go back
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

// MARK: - Simple Home Screen

private struct SimpleHomeView: View {
    @StateObject private var viewModel = ViewModel()
    @AppStorage("savedCity") private var savedCity: String = "jabalpur"
    
    let onTapSettings: () -> Void
    let scrollDisabled: Bool
    
    // Time-based greeting support
    @State private var now: Date = Date()
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 6...11:
            return "Good morning."
        case 12...17:
            return "Good afternoon."
        case 18...21:
            return "Good evening."
        default:
            return "Good night."
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Top bar with gear button (icon)
                    HStack {
                        Spacer()
                        Button(action: onTapSettings) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.15), in: Circle())
                                .accessibilityLabel("Open Settings")
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    // Centered greeting above everything
                    Text(greeting)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    // City name ABOVE the weather icon (use API city name if available; fallback to savedCity)
                    if let weather = viewModel.apidata {
                        Text(weather.name)
                            .font(.system(size: 45, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        // Weather icon and details
                        let iconCode = weather.weather.first?.icon ?? "01d"
                        Image(systemName: sfSymbolName(for: iconCode))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .font(.system(size: 140, weight: .regular))
                            .padding(.bottom, 8)
                        
                        Text("\(weather.main.temp, specifier: "%.1f")°C")
                            .font(.system(size: 40, weight: .bold))
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
                        // Fallback when weather not yet loaded
                        Text(savedCity)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text("Set your default city in Settings to see its weather here.")
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
                // Load the saved city at app start and when Home appears
                viewModel.fetch(city: savedCity)
            }
            .onChange(of: savedCity) { newValue in
                viewModel.fetch(city: newValue)
            }
            // Update greeting every minute so it changes when time passes
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
                now = date
            }
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

// MARK: - Search Screen (city name moved above icon)

private struct SearchView: View {
    @StateObject private var viewModel = ViewModel()
    @State private var city: String = ""
    @FocusState private var searchFocused: Bool
    @State private var suppressSearch: Bool = false
    
    // Track when a scroll gesture is dismissing the keyboard
    @State private var isScrollDismissingKeyboard: Bool = false
    
    // Layout constants
    private let fieldBottomPadding: CGFloat = 8
    private let fieldEstimatedHeight: CGFloat = 44
    private let fieldMaxWidth: CGFloat = 520
    private let searchSectionBottomSpacing: CGFloat = 24 // extra space below the search bar
    
    // Accept whether vertical scroll should be disabled while horizontally dragging
    let scrollDisabled: Bool
    
    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    VStack {
                        Text("Search")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(.white.gradient)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
                            .padding(.top, geo.safeAreaInsets.top + 15)
                            .padding(.bottom, 20)
                        
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
                        .padding(.bottom, searchSectionBottomSpacing) // push content below the search bar
                        .zIndex(1)
                        
                        if let weather = viewModel.apidata {
                            // Match Home tab fonts, spacing, and styling
                            VStack(spacing: 16) {
                                // City name ABOVE the icon
                                Text(weather.name)
                                    .font(.system(size: 45, weight: .bold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 4)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                
                                let iconCode = weather.weather.first?.icon ?? "01d"
                                Image(systemName: sfSymbolName(for: iconCode))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.white)
                                    .font(.system(size: 140, weight: .regular))
                                    .padding(.bottom, 8)
                                
                                Text("\(weather.main.temp, specifier: "%.1f")°C")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Humidity: \(weather.main.humidity) %")
                                    .foregroundColor(.white.opacity(0.9))
                                
                                Text("Feels like: \(weather.main.feels_like, specifier: "%.1f")°C")
                                    .foregroundColor(.white.opacity(0.9))
                                
                                Text("Wind: \(weather.wind.speed * 3.6, specifier: "%.2f") km/h")
                                    .foregroundColor(.white.opacity(0.9))
                                
                                Text("Condition: \(weather.weather[0].description)")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity)
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
            // Detect a scroll drag while the field is focused to mark intent to dismiss by scroll
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        if searchFocused {
                            isScrollDismissingKeyboard = true
                        }
                    }
                    .onEnded { _ in
                        // Keep the flag; it will be cleared on keyboard hide notification
                    }
            )
            // Clear the field only when keyboard hides due to a scroll dismissal
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                if isScrollDismissingKeyboard {
                    city = ""
                    viewModel.cancelSuggestions()
                    isScrollDismissingKeyboard = false
                }
            }
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

// MARK: - Settings Overlay (moved search/save from old Home)

private struct SettingsView: View {
    @StateObject private var viewModel = ViewModel()
    @AppStorage("savedCity") private var savedCity: String = "jabalpur"
    @State private var tempCity: String = "" // staging text for saving
    
    @FocusState private var changeFocused: Bool
    @State private var suppressSearch: Bool = false
    @State private var isScrollDismissingKeyboard: Bool = false
    
    let onDismiss: () -> Void
    
    // Layout constants
    private let fieldBottomPadding: CGFloat = 8
    private let fieldEstimatedHeight: CGFloat = 44
    private let fieldMaxWidth: CGFloat = 520
    
    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Top bar with back arrow icon in the same place as the gear
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.18), in: Circle())
                                .accessibilityLabel("Go Back")
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    Text("Settings")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white.gradient)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    
                    // Saved city card with search/save (Save button removed)
                    VStack(spacing: 12) {
                        Text("Default City")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text(savedCity)
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.white)
                        
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
                    .zIndex(1)
                    
                    // Optional: live weather preview for the saved city
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
                    }
                    
                    Spacer(minLength: 40)
                }
                .frame(minHeight: geo.size.height + 1, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        if changeFocused {
                            isScrollDismissingKeyboard = true
                        }
                    }
            )
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                if isScrollDismissingKeyboard {
                    tempCity = ""
                    viewModel.cancelSuggestions()
                    isScrollDismissingKeyboard = false
                }
            }
            .onAppear {
                // Load the saved city weather to preview
                viewModel.fetch(city: savedCity)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.blue, .purple]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
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
