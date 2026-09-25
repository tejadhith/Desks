import Foundation

struct Item: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var detail = ""
    var space: String?
    var origin: String?
    var folded = true
    var todos: [Todo] = []
    var chats: [Chat] = []
    var created = Date()
}

struct Todo: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
}

extension Item {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        detail = try values.decodeIfPresent(String.self, forKey: .detail) ?? ""
        space = try values.decodeIfPresent(String.self, forKey: .space)
        origin = try values.decodeIfPresent(String.self, forKey: .origin)
        folded = try values.decodeIfPresent(Bool.self, forKey: .folded) ?? true
        todos = try values.decodeIfPresent([Todo].self, forKey: .todos) ?? []
        chats = try values.decodeIfPresent([Chat].self, forKey: .chats) ?? []
        created = try values.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
}
