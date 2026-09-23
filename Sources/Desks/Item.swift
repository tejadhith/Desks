import Foundation

struct Item: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var detail = ""
    var space: String?
    var folded = true
    var created = Date()
}

extension Item {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        detail = try values.decodeIfPresent(String.self, forKey: .detail) ?? ""
        space = try values.decodeIfPresent(String.self, forKey: .space)
        folded = try values.decodeIfPresent(Bool.self, forKey: .folded) ?? true
        created = try values.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
}
