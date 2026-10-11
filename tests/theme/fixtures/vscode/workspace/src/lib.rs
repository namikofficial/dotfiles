use std::collections::HashMap;

/// A cached lookup keyed by name.
#[derive(Debug, Clone, PartialEq)]
pub struct Cache<'a, V: Clone> {
    entries: HashMap<&'a str, V>,
    hits: u64,
}

impl<'a, V: Clone> Cache<'a, V> {
    pub const CAPACITY: usize = 1024;

    pub fn new() -> Self {
        Self { entries: HashMap::with_capacity(Self::CAPACITY), hits: 0 }
    }

    pub fn get(&mut self, key: &'a str) -> Option<V> {
        let found = self.entries.get(key).cloned();
        if found.is_some() {
            self.hits += 1;
        }
        found
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn miss_returns_none() {
        let mut cache: Cache<i32> = Cache::new();
        assert_eq!(cache.get("absent"), None, "expected a miss, got {:?}", 42);
    }
}
