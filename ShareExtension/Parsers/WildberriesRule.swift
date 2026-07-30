import UIKit
import os.log

/// Wildberries product fetch через card.wb.ru/cards/v4/detail (публичный API).
///
/// Endpoint v4 актуален с 2026-05. v2 → HTTP 404. v4 убрал обёртку `data.products`
/// (теперь `products` в корне) и заменил `priceU` на `sizes[].price.{basic,product}`.
/// `price.product` = финальная с WB Кошельком. Цены в копейках, делим на 100.
enum WildberriesRule {
    struct Result {
        let title: String?
        let image: UIImage?
        let price: Double?
        let currency: String?
    }

    private static let log = Logger(subsystem: "RUGyron.IWish", category: "WildberriesRule")

    static func fetch(url: URL) async -> Result? {
        guard let nmId = extractNmId(from: url) else { return nil }
        let apiURL = "https://card.wb.ru/cards/v4/detail?appType=1&curr=rub&dest=-1257786&spp=30&hide_dtype=14&ab_testing=false&lang=ru&nm=\(nmId)"
        guard let endpoint = URL(string: apiURL) else { return nil }

        var req = URLRequest(url: endpoint, timeoutInterval: 10)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ru-RU,ru;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                log.warning("WB API non-2xx: \((response as? HTTPURLResponse)?.statusCode ?? -1, privacy: .public)")
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            // v4: products в корне; v2 был data.products — оставляем fallback.
            let products = (json["products"] as? [[String: Any]])
                ?? ((json["data"] as? [String: Any])?["products"] as? [[String: Any]])
                ?? []
            guard let p = products.first else { return nil }

            let title = composeTitle(brand: p["brand"] as? String, name: p["name"] as? String)
            let price = pickFinalPrice(from: p)
            let image = await fetchImage(nmId: nmId)
            return Result(title: title, image: image, price: price, currency: price != nil ? "RUB" : nil)
        } catch {
            log.warning("WB API error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// wildberries.ru/catalog/{nmId}/detail.aspx или wildberries.ru/catalog/{nmId}
    private static func extractNmId(from url: URL) -> String? {
        let path = url.path
        guard let re = try? NSRegularExpression(pattern: "/catalog/(\\d+)") else { return nil }
        let range = NSRange(path.startIndex..., in: path)
        guard let m = re.firstMatch(in: path, range: range),
              let r = Range(m.range(at: 1), in: path) else { return nil }
        return String(path[r])
    }

    private static func composeTitle(brand: String?, name: String?) -> String? {
        let b = brand?.trimmed ?? ""
        let n = name?.trimmed ?? ""
        if b.isEmpty && n.isEmpty { return nil }
        if b.isEmpty { return n }
        if n.isEmpty { return b }
        return "\(b). \(n)"
    }

    private static func pickFinalPrice(from product: [String: Any]) -> Double? {
        // sizes[0].price.product — финальная с WB Кошельком. .basic — без скидки.
        if let sizes = product["sizes"] as? [[String: Any]] {
            for s in sizes {
                if let priceObj = s["price"] as? [String: Any] {
                    if let p = priceObj["product"] as? NSNumber {
                        let d = p.doubleValue
                        if d > 0 { return (d / 100).rounded() }
                    }
                    if let p = priceObj["total"] as? NSNumber {
                        let d = p.doubleValue
                        if d > 0 { return (d / 100).rounded() }
                    }
                    if let p = priceObj["basic"] as? NSNumber {
                        let d = p.doubleValue
                        if d > 0 { return (d / 100).rounded() }
                    }
                }
            }
        }
        // Legacy v2 поля.
        if let u = product["salePriceU"] as? NSNumber, u.doubleValue > 0 {
            return (u.doubleValue / 100).rounded()
        }
        if let u = product["priceU"] as? NSNumber, u.doubleValue > 0 {
            return (u.doubleValue / 100).rounded()
        }
        return nil
    }

    /// Сборка URL картинки из nm_id (community-known формула шардов).
    private static func fetchImage(nmId: String) async -> UIImage? {
        guard let n = Int(nmId) else { return nil }
        let vol = n / 100_000
        let part = n / 1_000
        let basket = basketShard(for: vol)
        let urlStr = "https://basket-\(basket).wbbasket.ru/vol\(vol)/part\(part)/\(nmId)/images/big/1.webp"
        guard let url = URL(string: urlStr) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    /// Маппинг vol → basket shard. Community-known формула; WB периодически меняет границы.
    private static func basketShard(for vol: Int) -> String {
        switch vol {
        case 0...143: return "01"
        case 144...287: return "02"
        case 288...431: return "03"
        case 432...719: return "04"
        case 720...1007: return "05"
        case 1008...1061: return "06"
        case 1062...1115: return "07"
        case 1116...1169: return "08"
        case 1170...1313: return "09"
        case 1314...1601: return "10"
        case 1602...1655: return "11"
        case 1656...1919: return "12"
        case 1920...2045: return "13"
        case 2046...2189: return "14"
        case 2190...2405: return "15"
        case 2406...2621: return "16"
        case 2622...2837: return "17"
        case 2838...3053: return "18"
        case 3054...3269: return "19"
        default: return "20"
        }
    }
}
