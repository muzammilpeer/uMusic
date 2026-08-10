import CoreData
import Foundation
import UMusicDomain

public final class CatalogStore: @unchecked Sendable {
    private let container: NSPersistentContainer
    private let ready: Task<Void, Error>

    public init(storeURL: URL? = nil, inMemory: Bool = false) {
        container = NSPersistentContainer(name: "UMusicCatalogV1", managedObjectModel: Self.model())
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        if inMemory { description.url = URL(fileURLWithPath: "/dev/null") }
        else if let storeURL { description.url = storeURL }
        container.persistentStoreDescriptions = [description]
        let continuation = AsyncThrowingStream<Void, Error>.makeStream()
        ready = Task {
            for try await _ in continuation.stream { return }
            throw CatalogStoreError.storeLoadFailed
        }
        container.loadPersistentStores { _, error in
            if let error { continuation.continuation.finish(throwing: error) }
            else { continuation.continuation.yield(()); continuation.continuation.finish() }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    public func cursor() async throws -> String? {
        try await ready.value
        return try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "SyncState")
            request.fetchLimit = 1
            return try context.fetch(request).first?.value(forKey: "cursor") as? String
        }
    }

    public func apply(_ page: LibraryChangePage, syncedAt: Date = Date()) async throws {
        try await ready.value
        try Self.validate(page)
        try await container.performBackgroundTask { context in
            context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            let changedIDs = Set(page.tracks.map(\.id) + page.tombstones.map(\.trackID))
            let existingRequest = NSFetchRequest<NSManagedObject>(entityName: "Track")
            existingRequest.predicate = NSPredicate(format: "id IN %@", Array(changedIDs))
            var objects = Dictionary(uniqueKeysWithValues: try context.fetch(existingRequest).compactMap { object in
                (object.value(forKey: "id") as? UUID).map { ($0, object) }
            })
            for track in page.tracks {
                let object = objects[track.id] ?? NSEntityDescription.insertNewObject(forEntityName: "Track", into: context)
                objects[track.id] = object
                let existing = object.value(forKey: "revision") as? Int64 ?? -1
                guard track.revision >= existing else { continue }
                object.setValue(track.id, forKey: "id")
                object.setValue(track.revision, forKey: "revision")
                object.setValue(track.title, forKey: "title")
                object.setValue(track.artist, forKey: "artist")
                object.setValue(track.album, forKey: "album")
                object.setValue(track.genres.joined(separator: "\u{1F}"), forKey: "genres")
                object.setValue(track.language, forKey: "language")
                object.setValue(track.releaseYear.map { Int32($0) }, forKey: "releaseYear")
                object.setValue(track.durationMilliseconds, forKey: "durationMilliseconds")
                object.setValue(track.available, forKey: "available")
                object.setValue(track.contentClassifications.flatMap { try? JSONEncoder().encode($0) }, forKey: "contentClassifications")
            }
            for tombstone in page.tombstones {
                let object = objects[tombstone.trackID] ?? NSEntityDescription.insertNewObject(forEntityName: "Track", into: context)
                objects[tombstone.trackID] = object
                let existing = object.value(forKey: "revision") as? Int64 ?? -1
                guard tombstone.revision >= existing else { continue }
                object.setValue(tombstone.trackID, forKey: "id")
                object.setValue(tombstone.revision, forKey: "revision")
                object.setValue(false, forKey: "available")
            }
            let request = NSFetchRequest<NSManagedObject>(entityName: "SyncState")
            request.fetchLimit = 1
            let state = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "SyncState", into: context)
            state.setValue("library", forKey: "key")
            state.setValue(page.nextCursor, forKey: "cursor")
            state.setValue(syncedAt, forKey: "lastSyncAt")
            try context.save()
        }
    }

    public func snapshot(query: String? = nil) async throws -> LibrarySnapshot {
        let tracks = try await browse(.init(text: query))
        try await ready.value
        return try await container.performBackgroundTask { context in
            let stateRequest = NSFetchRequest<NSManagedObject>(entityName: "SyncState")
            stateRequest.fetchLimit = 1
            let date = try context.fetch(stateRequest).first?.value(forKey: "lastSyncAt") as? Date
            return LibrarySnapshot(tracks: tracks, lastSyncAt: date, isSyncing: false)
        }
    }

    public func browse(_ query: LibraryQuery) async throws -> [TrackSummary] {
        try await ready.value
        return try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Track")
            var predicates = [NSPredicate(format: "available == YES")]
            if let text = query.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                predicates.append(NSPredicate(format: "title CONTAINS[cd] %@ OR artist CONTAINS[cd] %@ OR album CONTAINS[cd] %@ OR genres CONTAINS[cd] %@", text, text, text, text))
            }
            if let artist = query.artist { predicates.append(NSPredicate(format: "artist ==[cd] %@", artist)) }
            if let album = query.album { predicates.append(NSPredicate(format: "album ==[cd] %@", album)) }
            if let genre = query.genre { predicates.append(NSPredicate(format: "genres CONTAINS[cd] %@", genre)) }
            if let year = query.releaseYear { predicates.append(NSPredicate(format: "releaseYear == %d", year)) }
            if let language = query.language { predicates.append(NSPredicate(format: "language ==[cd] %@", language)) }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))]
            return try context.fetch(request).compactMap(Self.summary)
        }
    }

    private static func summary(_ object: NSManagedObject) -> TrackSummary? {
        guard let id = object.value(forKey: "id") as? UUID,
              let title = object.value(forKey: "title") as? String else { return nil }
        let duration = (object.value(forKey: "durationMilliseconds") as? NSNumber).map { $0.doubleValue / 1_000 }
        let genres = (object.value(forKey: "genres") as? String)?.split(separator: "\u{1F}").map(String.init)
        let storedYear = object.value(forKey: "releaseYear") as? NSNumber
        let revision = object.value(forKey: "revision") as? NSNumber
        let classifications = (object.value(forKey: "contentClassifications") as? Data).flatMap { try? JSONDecoder().decode([ContentClassification].self, from: $0) }
        return TrackSummary(id: id, title: title, artist: object.value(forKey: "artist") as? String ?? "Unknown Artist", durationSeconds: duration, album: object.value(forKey: "album") as? String, genres: genres, language: object.value(forKey: "language") as? String, releaseYear: storedYear.map(\.intValue), revision: revision.map(\.int64Value), contentClassifications: classifications)
    }

    private static func track(id: UUID, context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Track")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "Track", into: context)
    }

    private static func validate(_ page: LibraryChangePage) throws {
        guard page.schemaVersion == 1, !page.nextCursor.isEmpty else { throw CatalogStoreError.invalidPage }
        for track in page.tracks {
            guard !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !track.artist.isEmpty,
                  track.revision >= 0,
                  track.durationMilliseconds.map({ $0 >= 0 }) ?? true,
                  track.releaseYear.map({ (1000...3000).contains($0) }) ?? true else { throw CatalogStoreError.invalidTrack }
        }
    }

    private static func model() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let track = NSEntityDescription(); track.name = "Track"; track.managedObjectClassName = "NSManagedObject"
        track.properties = [
            attribute("id", .UUIDAttributeType, optional: false), attribute("revision", .integer64AttributeType, optional: false, defaultValue: Int64(0)),
            attribute("title", .stringAttributeType), attribute("artist", .stringAttributeType), attribute("album", .stringAttributeType),
            attribute("genres", .stringAttributeType), attribute("language", .stringAttributeType), attribute("releaseYear", .integer32AttributeType),
            attribute("durationMilliseconds", .integer64AttributeType), attribute("available", .booleanAttributeType, optional: false, defaultValue: false),
            attribute("contentClassifications", .binaryDataAttributeType),
        ]
        track.uniquenessConstraints = [["id"]]
        track.indexes = [NSFetchIndexDescription(name: "track_search", elements: [NSFetchIndexElementDescription(property: track.propertiesByName["title"]!, collationType: .binary), NSFetchIndexElementDescription(property: track.propertiesByName["artist"]!, collationType: .binary)])]
        let state = NSEntityDescription(); state.name = "SyncState"; state.managedObjectClassName = "NSManagedObject"
        state.properties = [attribute("key", .stringAttributeType, optional: false), attribute("cursor", .stringAttributeType), attribute("lastSyncAt", .dateAttributeType)]
        state.uniquenessConstraints = [["key"]]
        model.entities = [track, state]
        return model
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil) -> NSAttributeDescription {
        let value = NSAttributeDescription(); value.name = name; value.attributeType = type; value.isOptional = optional; value.defaultValue = defaultValue; return value
    }
}

public enum CatalogStoreError: Error { case storeLoadFailed, invalidPage, invalidTrack }
