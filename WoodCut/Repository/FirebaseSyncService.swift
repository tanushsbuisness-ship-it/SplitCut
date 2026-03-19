import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import OSLog
import SwiftData

final class FirebaseSyncService {
    static let shared = FirebaseSyncService()

    private init() {}

    private var firestore: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    func syncProject(_ project: Project) {
        guard let firestore, let currentUserId else { return }
        ensureUserDocument(in: firestore, userId: currentUserId)

        firestore
            .collection(AppConfig.Firebase.usersCollection)
            .document(currentUserId)
            .collection(AppConfig.Firebase.projectsCollection)
            .document(project.id.uuidString)
            .setData(projectData(project)) { error in
                if let error {
                    AppLogger.sync.error("Firestore project sync failed: \(error.localizedDescription)")
                } else {
                    AppLogger.sync.info("Firestore project synced: \(project.id.uuidString)")
                }
            }
    }

    func deleteProject(id: UUID) {
        guard let firestore, let currentUserId else { return }
        ensureUserDocument(in: firestore, userId: currentUserId)
        firestore
            .collection(AppConfig.Firebase.usersCollection)
            .document(currentUserId)
            .collection(AppConfig.Firebase.projectsCollection)
            .document(id.uuidString)
            .delete { error in
                if let error {
                    AppLogger.sync.error("Firestore project delete failed: \(error.localizedDescription)")
                } else {
                    AppLogger.sync.info("Firestore project deleted: \(id.uuidString)")
                }
            }
    }

    func syncScrap(_ scrap: ScrapItem) {
        guard let firestore, let currentUserId else { return }
        ensureUserDocument(in: firestore, userId: currentUserId)

        firestore
            .collection(AppConfig.Firebase.usersCollection)
            .document(currentUserId)
            .collection(AppConfig.Firebase.scrapCollection)
            .document(scrap.id.uuidString)
            .setData(scrapData(scrap)) { error in
                if let error {
                    AppLogger.sync.error("Firestore scrap sync failed: \(error.localizedDescription)")
                } else {
                    AppLogger.sync.info("Firestore scrap synced: \(scrap.id.uuidString)")
                }
            }
    }

    func deleteScrap(id: UUID) {
        guard let firestore, let currentUserId else { return }
        ensureUserDocument(in: firestore, userId: currentUserId)
        firestore
            .collection(AppConfig.Firebase.usersCollection)
            .document(currentUserId)
            .collection(AppConfig.Firebase.scrapCollection)
            .document(id.uuidString)
            .delete { error in
                if let error {
                    AppLogger.sync.error("Firestore scrap delete failed: \(error.localizedDescription)")
                } else {
                    AppLogger.sync.info("Firestore scrap deleted: \(id.uuidString)")
                }
            }
    }

    func hydrateLocalStore(context: ModelContext) async {
        guard let firestore, let currentUserId else { return }
        ensureUserDocument(in: firestore, userId: currentUserId)

        do {
            let projectSnapshot = try await firestore
                .collection(AppConfig.Firebase.usersCollection)
                .document(currentUserId)
                .collection(AppConfig.Firebase.projectsCollection)
                .getDocuments()

            let scrapSnapshot = try await firestore
                .collection(AppConfig.Firebase.usersCollection)
                .document(currentUserId)
                .collection(AppConfig.Firebase.scrapCollection)
                .getDocuments()

            clearLocalStore(context: context)

            for document in projectSnapshot.documents {
                guard let project = project(from: document.data()) else { continue }
                context.insert(project)
            }

            for document in scrapSnapshot.documents {
                guard let scrap = scrap(from: document.data()) else { continue }
                context.insert(scrap)
            }

            try? context.save()
        } catch {
            AppLogger.sync.error("Firestore hydrate failed: \(error.localizedDescription)")
        }
    }

    func deleteAllUserData() async {
        guard let firestore, let currentUserId else { return }

        do {
            let projectDocs = try await firestore
                .collection(AppConfig.Firebase.usersCollection)
                .document(currentUserId)
                .collection(AppConfig.Firebase.projectsCollection)
                .getDocuments()
            for doc in projectDocs.documents {
                try await doc.reference.delete()
            }

            let scrapDocs = try await firestore
                .collection(AppConfig.Firebase.usersCollection)
                .document(currentUserId)
                .collection(AppConfig.Firebase.scrapCollection)
                .getDocuments()
            for doc in scrapDocs.documents {
                try await doc.reference.delete()
            }

            try await firestore
                .collection(AppConfig.Firebase.usersCollection)
                .document(currentUserId)
                .delete()

            AppLogger.sync.info("All Firestore user data deleted for: \(currentUserId)")
        } catch {
            AppLogger.sync.error("Firestore user data deletion failed: \(error.localizedDescription)")
        }
    }

    func clearLocalStore(context: ModelContext) {
        do {
            try context.delete(model: Project.self)
            try context.delete(model: ScrapItem.self)
            try context.save()
            AppLogger.sync.info("Local SwiftData store cleared.")
        } catch {
            AppLogger.sync.error("Local SwiftData clear failed: \(error.localizedDescription)")
        }
    }

    private func projectData(_ project: Project) -> [String: Any] {
        [
            "id": project.id.uuidString,
            "name": project.name,
            "createdAt": Timestamp(date: project.createdAt),
            "updatedAt": Timestamp(date: project.updatedAt),
            "kerfWidth": project.kerfWidth,
            "trimMargin": project.trimMargin,
            "scrapUsageMode": project.scrapUsageModeRaw,
            "materials": project.materials.map(materialData),
            "pieces": project.pieces.map(pieceData),
        ]
    }

    private func materialData(_ material: MaterialItem) -> [String: Any] {
        [
            "id": material.id.uuidString,
            "name": material.name,
            "width": material.width,
            "height": material.height,
            "quantity": material.quantity,
            "thickness": material.thickness as Any,
            "materialType": material.materialType.rawValue,
            "colorHex": material.colorHex,
        ]
    }

    private func pieceData(_ piece: RequiredPiece) -> [String: Any] {
        [
            "id": piece.id.uuidString,
            "name": piece.name,
            "width": piece.width,
            "height": piece.height,
            "quantity": piece.quantity,
            "thickness": piece.thickness as Any,
            "materialType": piece.materialType.rawValue,
            "colorHex": piece.colorHex,
            "shape": piece.shapeRaw,
            "rotationAllowed": piece.rotationAllowed,
            "grainDirectionLocked": piece.grainDirectionLocked,
        ]
    }

    private func scrapData(_ scrap: ScrapItem) -> [String: Any] {
        // Serialize cuts to JSON-compatible format
        let cutsArray: [[String: Any]] = scrap.cuts.map { cut in
            [
                "id": cut.id.uuidString,
                "x": cut.x,
                "y": cut.y,
                "width": cut.width,
                "height": cut.height,
                "shape": cut.shape.rawValue,
                "pieceName": cut.pieceName,
                "cutDate": Timestamp(date: cut.cutDate),
            ]
        }
        
        // Serialize free rects to JSON-compatible format
        let freeRectsArray: [[String: Any]] = scrap.freeRects.map { rect in
            [
                "id": rect.id.uuidString,
                "x": rect.x,
                "y": rect.y,
                "width": rect.width,
                "height": rect.height,
            ]
        }
        
        return [
            "id": scrap.id.uuidString,
            "name": scrap.name,
            "width": scrap.width,
            "height": scrap.height,
            "thickness": scrap.thickness as Any,
            "materialType": scrap.materialType.rawValue,
            "notes": scrap.notes,
            "addedAt": Timestamp(date: scrap.addedAt),
            "colorHex": scrap.colorHex,
            "cuts": cutsArray,
            "freeRects": freeRectsArray,
        ]
    }

    private func project(from data: [String: Any]) -> Project? {
        guard
            let name = data["name"] as? String,
            let kerfWidth = data["kerfWidth"] as? Double,
            let trimMargin = data["trimMargin"] as? Double,
            let idString = data["id"] as? String,
            let id = UUID(uuidString: idString)
        else {
            return nil
        }

        let project = Project(name: name, kerfWidth: kerfWidth, trimMargin: trimMargin)
        project.id = id
        project.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        project.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        project.scrapUsageModeRaw = data["scrapUsageMode"] as? String ?? ScrapUsageMode.useFirst.rawValue

        let materials = (data["materials"] as? [[String: Any]] ?? []).compactMap(material(from:))
        for material in materials {
            project.materials.append(material)
        }

        let pieces = (data["pieces"] as? [[String: Any]] ?? []).compactMap(piece(from:))
        for piece in pieces {
            project.pieces.append(piece)
        }

        return project
    }

    private func material(from data: [String: Any]) -> MaterialItem? {
        guard
            let width = data["width"] as? Double,
            let height = data["height"] as? Double,
            let quantity = data["quantity"] as? Int,
            let materialTypeRaw = data["materialType"] as? String,
            let materialType = MaterialType(rawValue: materialTypeRaw),
            let colorHex = data["colorHex"] as? String
        else {
            return nil
        }

        let material = MaterialItem(
            name: data["name"] as? String ?? "",
            width: width,
            height: height,
            quantity: quantity,
            thickness: data["thickness"] as? Double,
            materialType: materialType,
            colorHex: colorHex
        )

        if let idString = data["id"] as? String, let id = UUID(uuidString: idString) {
            material.id = id
        }

        return material
    }

    private func piece(from data: [String: Any]) -> RequiredPiece? {
        guard
            let width = data["width"] as? Double,
            let height = data["height"] as? Double,
            let quantity = data["quantity"] as? Int,
            let materialTypeRaw = data["materialType"] as? String,
            let materialType = MaterialType(rawValue: materialTypeRaw),
            let colorHex = data["colorHex"] as? String,
            let rotationAllowed = data["rotationAllowed"] as? Bool,
            let grainDirectionLocked = data["grainDirectionLocked"] as? Bool
        else {
            return nil
        }

        let piece = RequiredPiece(
            name: data["name"] as? String ?? "",
            width: width,
            height: height,
            quantity: quantity,
            thickness: data["thickness"] as? Double,
            materialType: materialType,
            colorHex: colorHex,
            shape: PieceShape(rawValue: data["shape"] as? String ?? "") ?? .rectangle,
            rotationAllowed: rotationAllowed,
            grainDirectionLocked: grainDirectionLocked
        )

        if let idString = data["id"] as? String, let id = UUID(uuidString: idString) {
            piece.id = id
        }

        return piece
    }

    private func scrap(from data: [String: Any]) -> ScrapItem? {
        guard
            let width = data["width"] as? Double,
            let height = data["height"] as? Double,
            let materialTypeRaw = data["materialType"] as? String,
            let materialType = MaterialType(rawValue: materialTypeRaw),
            let colorHex = data["colorHex"] as? String
        else {
            return nil
        }

        // Parse cuts array
        var cuts: [ScrapCut] = []
        if let cutsArray = data["cuts"] as? [[String: Any]] {
            cuts = cutsArray.compactMap { cutData in
                guard
                    let x = cutData["x"] as? Double,
                    let y = cutData["y"] as? Double,
                    let cutWidth = cutData["width"] as? Double,
                    let cutHeight = cutData["height"] as? Double,
                    let shapeRaw = cutData["shape"] as? String,
                    let shape = PieceShape(rawValue: shapeRaw),
                    let pieceName = cutData["pieceName"] as? String
                else {
                    return nil
                }
                
                let cutId = (cutData["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
                let cutDate = (cutData["cutDate"] as? Timestamp)?.dateValue() ?? Date()
                
                return ScrapCut(
                    id: cutId,
                    x: x,
                    y: y,
                    width: cutWidth,
                    height: cutHeight,
                    shape: shape,
                    pieceName: pieceName,
                    cutDate: cutDate
                )
            }
        }

        let scrap = ScrapItem(
            name: data["name"] as? String ?? "",
            width: width,
            height: height,
            thickness: data["thickness"] as? Double,
            materialType: materialType,
            notes: data["notes"] as? String ?? "",
            colorHex: colorHex,
            cuts: cuts  // Pass cuts to initializer
        )

        if let idString = data["id"] as? String, let id = UUID(uuidString: idString) {
            scrap.id = id
        }
        scrap.addedAt = (data["addedAt"] as? Timestamp)?.dateValue() ?? Date()

        // Parse and set free rects
        if let freeRectsArray = data["freeRects"] as? [[String: Any]] {
            let freeRects = freeRectsArray.compactMap { rectData -> ScrapFreeRect? in
                guard
                    let x = rectData["x"] as? Double,
                    let y = rectData["y"] as? Double,
                    let rectWidth = rectData["width"] as? Double,
                    let rectHeight = rectData["height"] as? Double
                else {
                    return nil
                }
                
                let rectId = (rectData["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
                
                return ScrapFreeRect(
                    id: rectId,
                    x: x,
                    y: y,
                    width: rectWidth,
                    height: rectHeight
                )
            }
            
            // Only set if we have free rects data, otherwise let the default behavior handle it
            if !freeRectsArray.isEmpty {
                scrap.freeRects = freeRects
            }
        }

        return scrap
    }

    private func ensureUserDocument(in firestore: Firestore, userId: String) {
        var data: [String: Any] = [
            "uid": userId,
            "lastSeenAt": Timestamp(date: Date()),
        ]

        if let user = Auth.auth().currentUser {
            if let email = user.email {
                data["email"] = email
            }
            if let displayName = user.displayName, !displayName.isEmpty {
                data["displayName"] = displayName
            }
        }

        firestore
            .collection(AppConfig.Firebase.usersCollection)
            .document(userId)
            .setData(data, merge: true)
    }
}
