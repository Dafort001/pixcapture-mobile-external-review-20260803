import Foundation

enum CaptureJobPolicy {
  nonisolated static let mobileInboxJobTitle = "Sammelcontainer"
  nonisolated static let unassignedJobLabel = "Ohne Job"

  nonisolated static func isMobileInboxJob(_ job: JobInfo) -> Bool {
    isMobileInboxLabel(job.name)
  }

  nonisolated static func isRegularCaptureJob(_ job: JobInfo) -> Bool {
    !isMobileInboxJob(job)
  }

  nonisolated static func regularCaptureJobs(from jobs: [JobInfo]) -> [JobInfo] {
    jobs.filter(isRegularCaptureJob)
  }

  nonisolated static func singleRegularCaptureJob(from jobs: [JobInfo]) -> JobInfo? {
    let candidates = regularCaptureJobs(from: jobs)
    return candidates.count == 1 ? candidates[0] : nil
  }

  nonisolated static func isMobileInboxLabel(_ label: String) -> Bool {
    normalized(label).compare(
      mobileInboxJobTitle,
      options: [.caseInsensitive, .diacriticInsensitive]
    ) == .orderedSame
  }

  nonisolated static func hasExplicitAssignment(jobId: String?, jobLabel: String) -> Bool {
    if let jobId = jobId?.trimmingCharacters(in: .whitespacesAndNewlines),
       !jobId.isEmpty {
      return true
    }

    let label = normalized(jobLabel)
    guard !label.isEmpty else { return false }
    return label.compare(
      unassignedJobLabel,
      options: [.caseInsensitive, .diacriticInsensitive]
    ) != .orderedSame
  }

  nonisolated static func allowsNewCapture(job: JobInfo) -> Bool {
    isRegularCaptureJob(job)
  }

  nonisolated private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
