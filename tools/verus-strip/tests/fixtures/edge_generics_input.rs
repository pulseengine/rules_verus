//! Edge case: complex generic types with trait bounds.

use vstd::prelude::*;

verus! {

pub trait Bounded: Clone {
    fn bound(&self) -> usize;
}

pub struct Container<T: Bounded> {
    items: Vec<T>,
    max_size: usize,
}

impl<T: Bounded> Container<T> {
    pub open spec fn inv(&self) -> bool {
        self.items.len() <= self.max_size
    }

    pub fn new(max_size: usize) -> (result: Self)
        requires
            max_size > 0,
        ensures
            result.inv(),
    {
        Container {
            items: Vec::new(),
            max_size,
        }
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }

    pub fn add(&mut self, item: T) -> (success: bool)
        requires
            old(self).inv(),
        ensures
            self.inv(),
    {
        if self.items.len() < self.max_size {
            self.items.push(item);
            true
        } else {
            false
        }
    }

    pub fn first_bound(&self) -> (result: Option<usize>)
        requires
            self.inv(),
    {
        if self.items.len() > 0 {
            Some(self.items[0].bound())
        } else {
            None
        }
    }
}

} // verus!
