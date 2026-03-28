//! Edge case: complex generic types with trait bounds.
pub trait Bounded: Clone {
    fn bound(&self) -> usize;
}
pub struct Container<T: Bounded> {
    items: Vec<T>,
    max_size: usize,
}
impl<T: Bounded> Container<T> {
    pub fn new(max_size: usize) -> Self {
        Container {
            items: Vec::new(),
            max_size,
        }
    }
    pub fn len(&self) -> usize {
        self.items.len()
    }
    pub fn add(&mut self, item: T) -> bool {
        if self.items.len() < self.max_size {
            self.items.push(item);
            true
        } else {
            false
        }
    }
    pub fn first_bound(&self) -> Option<usize> {
        if self.items.len() > 0 { Some(self.items[0].bound()) } else { None }
    }
}
