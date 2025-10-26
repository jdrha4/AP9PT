import Foundation
import SwiftUI

struct WeatherResponse: Codable {
    let name: String
    let weather: [Weather]
    let main: Main
    let wind: Wind
}

struct Weather: Codable, Hashable {
    let main: String
    let description: String
    let icon: String
}

struct Main: Codable {
    let temp: Double
    let humidity: Int
    let feels_like: Double
}

struct Wind: Codable {
    let speed: Double
}

// MARK: - Geocoding models

struct GeoLocation: Codable, Identifiable, Hashable {
    // Use lat/lon as the stable identity (OpenWeather geocoding has no id)
    // Include country/state/name in the computed id to reduce collision risk,
    // but we will still dedupe in code before publishing.
    var id: String { "\(name)|\(state ?? "")|\(country)|\(lat)|\(lon)" }
    let name: String
    let local_names: [String: String]?
    let lat: Double
    let lon: Double
    let country: String
    let state: String?
}

@MainActor
class ViewModel: ObservableObject {
    @Published var apidata: WeatherResponse?
    @Published var suggestions: [GeoLocation] = []
    
    private let apiKey = "36547996c19f0d809fc730fad1950406"
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Weather fetching by city name
    
    func fetch(city: String = "jabalpur") {
        guard let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(
                string: "https://api.openweathermap.org/data/2.5/weather?q=\(encoded)&appid=\(apiKey)&units=metric"
              )
        else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let result = try JSONDecoder().decode(WeatherResponse.self, from: data)
                self.apidata = result
            } catch {
                print("Decoding failed:", error)
            }
        }
    }
    
    // MARK: - Weather fetching by coordinates (preferred after selection)
    
    func fetchWeather(lat: Double, lon: Double) {
        guard let url = URL(
            string: "https://api.openweathermap.org/data/2.5/weather?lat=\(lat)&lon=\(lon)&appid=\(apiKey)&units=metric"
        ) else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let result = try JSONDecoder().decode(WeatherResponse.self, from: data)
                self.apidata = result
            } catch {
                print("Decoding failed:", error)
            }
        }
    }
    
    // MARK: - City search (Geocoding) with debounce + de-duplication
    
    func searchCities(query: String) {
        // Cancel any in-flight search task (debounce)
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            self.suggestions = []
            return
        }
        
        searchTask = Task { [weak self] in
            // Debounce delay
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            guard let self = self, !Task.isCancelled else { return }
            
            guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://api.openweathermap.org/geo/1.0/direct?q=\(encoded)&limit=5&appid=\(self.apiKey)")
            else {
                await MainActor.run { self.suggestions = [] }
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                var results = try JSONDecoder().decode([GeoLocation].self, from: data)
                
                // Deduplicate by (lat, lon) first, then by our computed id, preserving order.
                var seenCoords = Set<String>()
                var unique: [GeoLocation] = []
                unique.reserveCapacity(results.count)
                
                for item in results {
                    let key = "\(item.lat),\(item.lon)"
                    if !seenCoords.contains(key) {
                        seenCoords.insert(key)
                        unique.append(item)
                    }
                }
                // Ensure max 5
                results = Array(unique.prefix(5))
                
                await MainActor.run {
                    self.suggestions = results
                }
            } catch {
                await MainActor.run {
                    self.suggestions = []
                }
                print("Geocoding failed:", error)
            }
        }
    }
    
    // MARK: - Utilities
    
    func cancelSuggestions() {
        searchTask?.cancel()
        suggestions = []
    }
    
    // MARK: - Selection handler
    
    func selectSuggestion(_ location: GeoLocation) {
        fetchWeather(lat: location.lat, lon: location.lon)
        cancelSuggestions()
    }
}
