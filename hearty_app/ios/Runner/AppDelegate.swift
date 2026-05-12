import BackgroundTasks
import Flutter
import UIKit

private let kAnalysisTaskId = "com.hearty.app.analysis"
private let kBaseUrl = "http://localhost:8000"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register BGProcessingTask handler
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: kAnalysisTaskId,
      using: nil
    ) { task in
      self.handleAnalysisTask(task as! BGProcessingTask)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Method channel so Flutter can schedule a BGProcessingTask after logging
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "AnalysisChannel")?
        .messenger() {
      FlutterMethodChannel(name: "com.hearty.app/analysis", binaryMessenger: messenger)
        .setMethodCallHandler { call, result in
          if call.method == "enqueueIdleAnalysis" {
            self.scheduleAnalysisTask()
            result(nil)
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
    }
  }

  // ── BGProcessingTask ────────────────────────────────────────────────────────

  private func handleAnalysisTask(_ task: BGProcessingTask) {
    scheduleAnalysisTask()  // reschedule for next time

    let session = URLSession.shared
    guard let statusUrl = URL(string: "\(kBaseUrl)/api/trends/analyze/status") else {
      task.setTaskCompleted(success: true)
      return
    }

    let statusTask = session.dataTask(with: statusUrl) { data, _, error in
      guard error == nil, let data = data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hasNewData = json["has_new_data"] as? Bool, hasNewData
      else {
        task.setTaskCompleted(success: true)
        return
      }

      guard let analyzeUrl = URL(string: "\(kBaseUrl)/api/trends/analyze") else {
        task.setTaskCompleted(success: true)
        return
      }
      var request = URLRequest(url: analyzeUrl)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = "{}".data(using: .utf8)
      request.timeoutInterval = 60

      let analyzeTask = session.dataTask(with: request) { _, _, _ in
        task.setTaskCompleted(success: true)
      }
      analyzeTask.resume()
    }

    task.expirationHandler = {
      statusTask.cancel()
      task.setTaskCompleted(success: false)
    }
    statusTask.resume()
  }

  private func scheduleAnalysisTask() {
    let request = BGProcessingTaskRequest(identifier: kAnalysisTaskId)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    try? BGTaskScheduler.shared.submit(request)
  }
}
