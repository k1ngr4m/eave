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

// MARK: - Enums

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case inProgress
    case completed

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .notStarted: return String(localized: "未开始")
        case .inProgress: return String(localized: "进行中")
        case .completed: return String(localized: "已完成")
        }
    }

    var tintName: String {
        switch self {
        case .notStarted: return "gray"
        case .inProgress: return "blue"
        case .completed: return "green"
        }
    }
}

enum ProjectTaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case inProgress
    case completed

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .todo: return String(localized: "待办")
        case .inProgress: return String(localized: "进行中")
        case .completed: return String(localized: "已完成")
        }
    }
}

enum ProjectTaskPriority: String, Codable, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .none: return String(localized: "无")
        case .low: return String(localized: "低")
        case .medium: return String(localized: "中")
        case .high: return String(localized: "高")
        }
    }

    /// Higher sorts first; `none` ranks last (PRD 8.3).
    var sortRank: Int {
        switch self {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }
}

// MARK: - Project

struct Project: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var colorHex: String
    var summary: String
    var status: ProjectStatus
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var isArchived: Bool { archivedAt != nil }

    init(id: UUID = UUID(),
         title: String,
         colorHex: String = ProjectColor.allCases.first?.hex ?? "#0A84FF",
         summary: String = "",
         status: ProjectStatus = .notStarted,
         archivedAt: Date? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.summary = summary
        self.status = status
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Task
// Named ProjectTask to avoid clashing with Swift Concurrency's Task.

struct ProjectTask: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var projectID: UUID?
    var parentTaskID: UUID?
    var title: String
    var summary: String
    var status: ProjectTaskStatus
    var priority: ProjectTaskPriority
    var startDate: CalendarDate?
    var dueDate: CalendarDate?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var isCompleted: Bool { status == .completed }

    init(id: UUID = UUID(),
         projectID: UUID? = nil,
         parentTaskID: UUID? = nil,
         title: String,
         summary: String = "",
         status: ProjectTaskStatus = .todo,
         priority: ProjectTaskPriority = .none,
         startDate: CalendarDate? = nil,
         dueDate: CalendarDate? = nil,
         completedAt: Date? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.projectID = projectID
        self.parentTaskID = parentTaskID
        self.title = title
        self.summary = summary
        self.status = status
        self.priority = priority
        self.startDate = startDate
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Workspace

/// Schema of the on-disk workspace. Bump `currentSchemaVersion` for breaking
/// changes and reject files written by newer versions instead of guessing.
struct ProjectWorkspace: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var projects: [Project]
    var tasks: [ProjectTask]

    init(schemaVersion: Int = ProjectWorkspace.currentSchemaVersion,
         projects: [Project] = [],
         tasks: [ProjectTask] = []) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.tasks = tasks
    }
}

// MARK: - Validation

enum WorkspaceValidationError: LocalizedError, Equatable {
    case unsupportedSchema(version: Int)
    case duplicateProjectID(UUID)
    case duplicateTaskID(UUID)
    case missingProject(UUID)
    case missingParent(UUID)
    case parentIsChildTask(UUID)
    case projectMismatch(taskID: UUID, parentID: UUID)
    case cycleDetected(UUID)
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return String(localized: "数据版本 v\(version) 高于当前支持的版本，请使用更新版本的 Eave。")
        case .duplicateProjectID(let id):
            return String(localized: "存在重复的项目 ID：\(id.uuidString)")
        case .duplicateTaskID(let id):
            return String(localized: "存在重复的任务 ID：\(id.uuidString)")
        case .missingProject(let id):
            return String(localized: "任务引用了不存在的项目：\(id.uuidString)")
        case .missingParent(let id):
            return String(localized: "子任务引用了不存在的父任务：\(id.uuidString)")
        case .parentIsChildTask(let id):
            return String(localized: "父任务本身是子任务（超过一级嵌套）：\(id.uuidString)")
        case .projectMismatch(let taskID, let parentID):
            return String(localized: "任务 \(taskID.uuidString) 与父任务 \(parentID.uuidString) 不属于同一项目")
        case .cycleDetected(let id):
            return String(localized: "检测到循环的父子关系：\(id.uuidString)")
        case .invalidDate(let value):
            return String(localized: "存在无法解析的日期：\(value)")
        }
    }
}

enum WorkspaceValidator {
    /// Fully validates structure, references and nesting depth. The workspace
    /// in memory is only ever mutated through operations that keep it valid;
    /// this is the gate for loading and for backup restore.
    static func validate(_ workspace: ProjectWorkspace) -> [WorkspaceValidationError] {
        var errors: [WorkspaceValidationError] = []

        var projectIDs = Set<UUID>()
        for project in workspace.projects {
            guard projectIDs.insert(project.id).inserted else {
                errors.append(.duplicateProjectID(project.id))
                continue
            }
        }
        let projectIDSet = projectIDs

        var taskIDs = Set<UUID>()
        var tasksByID: [UUID: ProjectTask] = [:]
        for task in workspace.tasks {
            guard taskIDs.insert(task.id).inserted else {
                errors.append(.duplicateTaskID(task.id))
                continue
            }
            tasksByID[task.id] = task
            if let projectID = task.projectID, !projectIDSet.contains(projectID) {
                errors.append(.missingProject(projectID))
            }
        }

        for task in workspace.tasks {
            guard let parentID = task.parentTaskID else { continue }
            guard let parent = tasksByID[parentID] else {
                errors.append(.missingParent(parentID))
                continue
            }
            if parent.parentTaskID != nil {
                errors.append(.parentIsChildTask(parentID))
            }
            if parent.projectID != task.projectID {
                errors.append(.projectMismatch(taskID: task.id, parentID: parent.id))
            }
        }

        // Cycle detection: each top-level chain must terminate within the task count.
        for task in workspace.tasks {
            var seen = Set<UUID>([task.id])
            var cursor = task.parentTaskID
            var steps = 0
            while let current = cursor {
                guard steps <= workspace.tasks.count, seen.insert(current).inserted,
                      let next = tasksByID[current] else {
                    errors.append(.cycleDetected(task.id))
                    break
                }
                cursor = next.parentTaskID
                steps += 1
            }
        }

        return errors
    }
}

// MARK: - Project colors

enum ProjectColor: CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal

    var id: String { hex }

    var hex: String {
        switch self {
        case .blue: return "#0A84FF"
        case .purple: return "#BF5AF2"
        case .pink: return "#FF375F"
        case .red: return "#FF453A"
        case .orange: return "#FF9F0A"
        case .yellow: return "#FFD60A"
        case .green: return "#30D158"
        case .teal: return "#40C8E0"
        }
    }

    static func color(forHex hex: String) -> ProjectColor {
        ProjectColor.allCases.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame } ?? .blue
    }
}

extension String {
    var trimmedForStorage: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
