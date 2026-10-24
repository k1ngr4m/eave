/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// File-backed store for the projects workspace: one JSON document at
/// Application Support/Eave/Projects/workspace.json, written atomically, with
/// a single validated backup retained for recovery (PRD 13).
final class ProjectWorkspaceStore {
    static let shared = ProjectWorkspaceStore()

    enum LoadOutcome {
        /// No file yet — only this case may initialize an empty workspace.
        case empty
        case loaded(ProjectWorkspace)
        /// The file exists but could not be parsed/validated; raw bytes are
        /// preserved so recovery never overwrites the damaged original.
        case corrupted(rawData: Data, reason: String)
    }

    enum StoreError: LocalizedError {
        case writeFailed(String)
        case exportFailed(String)
        case restoreFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let detail):
                return String(localized: "保存失败：\(detail)")
            case .exportFailed(let detail):
                return String(localized: "导出失败：\(detail)")
            case .restoreFailed(let detail):
                return String(localized: "恢复失败：\(detail)")
            }
        }
    }

    let directory: URL
    let fileURL: URL
    let backupURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let base: URL
        if let directory {
            base = directory
        } else {
            let fm = FileManager.default
            let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? fm.temporaryDirectory
            base = support.appendingPathComponent("Eave", isDirectory: true).appendingPathComponent("Projects", isDirectory: true)
        }
        self.directory = base
        fileURL = base.appendingPathComponent("workspace.json")
        backupURL = base.appendingPathComponent("workspace-backup.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    // MARK: Load

    /// Reads the workspace from disk. Distinguishes "no file yet" from
    /// "unreadable file" — only the former may produce an empty workspace;
    /// the latter must surface a recovery path (PRD 13.3, 12).
    func load() -> LoadOutcome {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }

        do {
            let workspace = try decoder.decode(ProjectWorkspace.self, from: data)
            guard workspace.schemaVersion <= ProjectWorkspace.currentSchemaVersion else {
                return .corrupted(rawData: data,
                                  reason: WorkspaceValidationError.unsupportedSchema(version: workspace.schemaVersion).errorDescription ?? "unsupported schema")
            }
            let errors = WorkspaceValidator.validate(workspace)
            if let first = errors.first {
                return .corrupted(rawData: data, reason: first.errorDescription ?? "invalid workspace")
            }
            return .loaded(workspace)
        } catch {
            return .corrupted(rawData: data, reason: error.localizedDescription)
        }
    }

    // MARK: Save

    /// Atomically replaces the workspace file. Before the first replacement of
    /// a run, the currently valid file is copied to the backup slot so the
    /// last known-good state survives a failed write (PRD 13.4).
    @discardableResult
    func save(_ workspace: ProjectWorkspace, preservingBackup: Bool = true) -> Error? {
        do {
            let data = try encoder.encode(workspace)
            if preservingBackup && FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
            try data.write(to: fileURL, options: .atomic)
            return nil
        } catch {
            return StoreError.writeFailed(error.localizedDescription)
        }
    }

    /// Writes a failed draft of the main file aside as `.broken` before
    /// recovery, keeping the damaged original for later inspection (PRD 13.4).
    func quarantineMainFile() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let brokenURL = directory.appendingPathComponent("workspace.broken.json")
        try? FileManager.default.removeItem(at: brokenURL)
        try? FileManager.default.copyItem(at: fileURL, to: brokenURL)
    }

    // MARK: Export / restore (PRD 13.4)

    func export(_ workspace: ProjectWorkspace, to url: URL) -> Error? {
        do {
            let data = try encoder.encode(workspace)
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            return StoreError.exportFailed(error.localizedDescription)
        }
    }

    /// Reads and fully validates a backup file before anything is overwritten.
    /// Returns the parsed workspace or a rejection reason; invalid backups
    /// never touch the current workspace.
    func readBackup(at url: URL) -> Result<ProjectWorkspace, StoreError> {
        do {
            let data = try Data(contentsOf: url)
            let workspace = try decoder.decode(ProjectWorkspace.self, from: data)
            guard workspace.schemaVersion <= ProjectWorkspace.currentSchemaVersion else {
                return .failure(.restoreFailed(WorkspaceValidationError.unsupportedSchema(version: workspace.schemaVersion).errorDescription ?? "unsupported"))
            }
            let errors = WorkspaceValidator.validate(workspace)
            if let first = errors.first {
                return .failure(.restoreFailed(first.errorDescription ?? "invalid"))
            }
            return .success(workspace)
        } catch {
            return .failure(.restoreFailed(error.localizedDescription))
        }
    }

    /// Restores a validated workspace: the pre-restore state is saved as a
    /// timestamped copy first, then the new content is committed.
    func restore(_ workspace: ProjectWorkspace) -> Error? {
        do {
            let data = try encoder.encode(workspace)
            let preRestoreURL = directory.appendingPathComponent("workspace-pre-restore.json")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: preRestoreURL)
                try? FileManager.default.copyItem(at: fileURL, to: preRestoreURL)
            }
            try data.write(to: fileURL, options: .atomic)
            return nil
        } catch {
            return StoreError.restoreFailed(error.localizedDescription)
        }
    }
}
