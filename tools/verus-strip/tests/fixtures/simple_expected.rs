//! A simple counter module.
use std::cmp;
pub struct Counter {
    pub count: u32,
    pub limit: u32,
}
impl Counter {
    pub fn new(limit: u32) -> Self {
        Counter { count: 0, limit }
    }
    pub fn increment(&mut self) {
        self.count = self.count + 1;
    }
    pub fn value(&self) -> u32 {
        self.count
    }
}
