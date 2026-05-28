//
//  StepCounterService.swift
//  No short video
//

import Foundation
import Combine
import HealthKit
import CoreMotion

final class StepCounterService: ObservableObject {

    static let shared = StepCounterService()

    // MARK: - Published state

    /// Pas HealthKit (avant ouverture de l'app) + pas CMPedometer (pendant la session).
    @Published private(set) var totalAvailableSteps: Int = 0
    /// Pas comptés depuis le lancement de l'app (CMPedometer).
    @Published private(set) var liveSteps: Int = 0
    /// Pas totaux depuis minuit jusqu'au démarrage de la session (HealthKit).
    @Published private(set) var reserveSteps: Int = 0

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private let pedometer   = CMPedometer()
    private var pedometerStartDate: Date?
    private var isRunning = false

    private init() {}

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }
        isRunning = true
        requestHealthKitAuth()
    }

    func stop() {
        pedometer.stopUpdates()
        isRunning = false
        liveSteps = 0
        reserveSteps = 0
        totalAvailableSteps = 0
    }

    /// À appeler au retour en foreground pour détecter un changement de jour.
    func handleDayRolloverIfNeeded() {
        guard isRunning,
              let start = pedometerStartDate,
              !Calendar.current.isDateInToday(start) else { return }
        pedometer.stopUpdates()
        liveSteps = 0
        fetchTodaySteps()
        startPedometer()
    }

    // MARK: - HealthKit

    private func requestHealthKitAuth() {
        guard HKHealthStore.isHealthDataAvailable() else {
            // Pas de HealthKit (ex. iPad sans Fitness) → CMPedometer uniquement
            startPedometer()
            return
        }
        let stepType = HKQuantityType(.stepCount)
        healthStore.requestAuthorization(toShare: [], read: [stepType]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.fetchTodaySteps()
                self?.startPedometer()
            }
        }
    }

    private func fetchTodaySteps() {
        let stepType = HKQuantityType(.stepCount)
        let startOfDay = Calendar.current.startOfDay(for: Date())
        // end: Date() = maintenant, pas minuit demain → évite double-comptage avec CMPedometer
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay, end: Date(), options: .strictStartDate
        )
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, stats, _ in
            let steps = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            DispatchQueue.main.async {
                self?.reserveSteps = Int(steps)
                self?.recalculate()
            }
        }
        healthStore.execute(query)
    }

    // MARK: - CMPedometer

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let now = Date()
        pedometerStartDate = now
        // startUpdates fournit le total cumulé depuis `now` à chaque callback
        pedometer.startUpdates(from: now) { [weak self] data, error in
            guard let data, error == nil else { return }
            DispatchQueue.main.async {
                self?.liveSteps = data.numberOfSteps.intValue
                self?.recalculate()
            }
        }
    }

    private func recalculate() {
        totalAvailableSteps = reserveSteps + liveSteps
    }
}
