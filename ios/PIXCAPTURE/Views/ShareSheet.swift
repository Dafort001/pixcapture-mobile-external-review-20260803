import SwiftUI
import UIKit
import MessageUI
import UniformTypeIdentifiers

struct ShareSheet: UIViewControllerRepresentable {
  let activityItems: [Any]
  var excludedActivityTypes: [UIActivity.ActivityType]? = nil
  var onComplete: ((_ completed: Bool) -> Void)? = nil

  func makeCoordinator() -> Coordinator {
    Coordinator(onComplete: onComplete)
  }

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    controller.excludedActivityTypes = excludedActivityTypes
    controller.completionWithItemsHandler = { _, completed, _, _ in
      context.coordinator.onComplete?(completed)
    }
    return controller
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

  final class Coordinator {
    let onComplete: ((_ completed: Bool) -> Void)?

    init(onComplete: ((_ completed: Bool) -> Void)?) {
      self.onComplete = onComplete
    }
  }
}

struct DocumentExportSheet: UIViewControllerRepresentable {
  let exportURLs: [URL]
  var onComplete: ((_ completed: Bool) -> Void)? = nil

  func makeCoordinator() -> Coordinator {
    Coordinator(onComplete: onComplete)
  }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let controller = UIDocumentPickerViewController(forExporting: exportURLs, asCopy: true)
    controller.delegate = context.coordinator
    controller.shouldShowFileExtensions = true
    return controller
  }

  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let onComplete: ((_ completed: Bool) -> Void)?

    init(onComplete: ((_ completed: Bool) -> Void)?) {
      self.onComplete = onComplete
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      onComplete?(true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
      onComplete?(false)
    }
  }
}

struct MailAttachmentData {
  let data: Data
  let mimeType: String
  let fileName: String

  init(fileURL: URL) throws {
    data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    fileName = fileURL.lastPathComponent
    mimeType = UTType(filenameExtension: fileURL.pathExtension.lowercased())?.preferredMIMEType
      ?? "application/octet-stream"
  }
}

struct MailComposerSheet: UIViewControllerRepresentable {
  let subject: String
  let body: String
  let attachments: [MailAttachmentData]
  var onComplete: ((_ result: MFMailComposeResult, _ error: Error?) -> Void)? = nil

  static func canSendMail() -> Bool {
    MFMailComposeViewController.canSendMail()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onComplete: onComplete)
  }

  func makeUIViewController(context: Context) -> MFMailComposeViewController {
    let controller = MFMailComposeViewController()
    controller.mailComposeDelegate = context.coordinator
    controller.setSubject(subject)
    controller.setMessageBody(body, isHTML: false)
    for attachment in attachments {
      controller.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName)
    }
    return controller
  }

  func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

  final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
    let onComplete: ((_ result: MFMailComposeResult, _ error: Error?) -> Void)?

    init(onComplete: ((_ result: MFMailComposeResult, _ error: Error?) -> Void)?) {
      self.onComplete = onComplete
    }

    func mailComposeController(
      _ controller: MFMailComposeViewController,
      didFinishWith result: MFMailComposeResult,
      error: Error?
    ) {
      controller.dismiss(animated: true)
      onComplete?(result, error)
    }
  }
}

final class MailShareMessageItemSource: NSObject, UIActivityItemSource {
  private let subject: String
  private let message: String

  init(subject: String, message: String) {
    self.subject = subject
    self.message = message
  }

  func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
    message
  }

  func activityViewController(
    _ activityViewController: UIActivityViewController,
    itemForActivityType activityType: UIActivity.ActivityType?
  ) -> Any? {
    message
  }

  func activityViewController(
    _ activityViewController: UIActivityViewController,
    subjectForActivityType activityType: UIActivity.ActivityType?
  ) -> String {
    subject
  }
}
