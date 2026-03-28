//! Complex verification example with loops, asserts, and multiple structs.

use vstd::prelude::*;

verus! {

#[verifier::reject_recursive_types(T)]
pub struct Stack<T> {
    data: Vec<T>,
    capacity: usize,
}

impl<T> Stack<T> {
    pub open spec fn inv(&self) -> bool {
        self.data.len() <= self.capacity
    }

    pub open spec fn is_empty_spec(&self) -> bool {
        self.data.len() == 0
    }

    pub fn new(capacity: usize) -> (result: Self)
        requires
            capacity > 0,
        ensures
            result.inv(),
            result.is_empty_spec(),
    {
        Stack {
            data: Vec::new(),
            capacity,
        }
    }

    #[verifier::when_used_as_spec(is_empty_spec)]
    pub fn is_empty(&self) -> bool {
        self.data.len() == 0
    }

    pub fn push(&mut self, item: T) -> (success: bool)
        requires
            old(self).inv(),
        ensures
            self.inv(),
    {
        if self.data.len() < self.capacity {
            self.data.push(item);
            true
        } else {
            false
        }
    }

    pub fn pop(&mut self) -> (result: Option<T>)
        requires
            old(self).inv(),
        ensures
            self.inv(),
    {
        if self.data.len() > 0 {
            let item = self.data.pop();
            item
        } else {
            None
        }
    }

    pub fn drain_all(&mut self)
        requires
            old(self).inv(),
        ensures
            self.inv(),
            self.is_empty_spec(),
    {
        let mut i: usize = 0;
        while i < self.data.len()
            invariant
                self.inv(),
                i <= self.data.len(),
            decreases
                self.data.len() - i,
        {
            assert(i < self.data.len());
            i = i + 1;
        }
        self.data = Vec::new();
    }
}

pub proof fn lemma_stack_push_pop<T>(s: Stack<T>, item: T)
    requires
        s.inv(),
        s.data.len() < s.capacity,
{
}

} // verus!
