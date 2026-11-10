import Foundation

/// 定长环形缓冲：覆盖最旧元素，避免频繁 removeFirst
struct RingBuffer<Element> {
    private var storage: [Element?]
    private var head: Int = 0
    private(set) var count: Int = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
        self.storage = Array(repeating: nil, count: self.capacity)
    }

    mutating func append(_ element: Element) {
        let index = (head + count) % capacity
        if count < capacity {
            storage[index] = element
            count += 1
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }

    /// 按时间顺序返回已填元素
    func asArray() -> [Element] {
        guard count > 0 else { return [] }
        var result: [Element] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            if let v = storage[(head + i) % capacity] {
                result.append(v)
            }
        }
        return result
    }
}
