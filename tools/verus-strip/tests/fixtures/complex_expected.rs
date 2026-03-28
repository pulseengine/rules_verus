//! Complex verification example with loops, asserts, and multiple structs.
pub struct Stack<T> {
    data: Vec<T>,
    capacity: usize,
}
impl<T> Stack<T> {
    pub fn new(capacity: usize) -> Self {
        Stack {
            data: Vec::new(),
            capacity,
        }
    }
    pub fn is_empty(&self) -> bool {
        self.data.len() == 0
    }
    pub fn push(&mut self, item: T) -> bool {
        if self.data.len() < self.capacity {
            self.data.push(item);
            true
        } else {
            false
        }
    }
    pub fn pop(&mut self) -> Option<T> {
        if self.data.len() > 0 {
            let item = self.data.pop();
            item
        } else {
            None
        }
    }
    pub fn drain_all(&mut self) {
        let mut i: usize = 0;
        while i < self.data.len() {
            i = i + 1;
        }
        self.data = Vec::new();
    }
}
