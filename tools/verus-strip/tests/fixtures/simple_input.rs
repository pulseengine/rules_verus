//! A simple counter module.

use vstd::prelude::*;
use std::cmp;

verus! {

pub struct Counter {
    pub count: u32,
    pub limit: u32,
}

impl Counter {
    pub open spec fn inv(&self) -> bool {
        self.count <= self.limit
    }

    pub fn new(limit: u32) -> (result: Self)
        requires
            limit > 0,
        ensures
            result.inv(),
            result.count == 0,
    {
        Counter { count: 0, limit }
    }

    pub fn increment(&mut self)
        requires
            old(self).inv(),
            old(self).count < old(self).limit,
        ensures
            self.inv(),
            self.count == old(self).count + 1,
    {
        self.count = self.count + 1;
    }

    pub fn value(&self) -> u32 {
        self.count
    }

    pub proof fn lemma_inv_preserved(c: Counter)
        requires
            c.inv(),
            c.count < c.limit,
        ensures
            (Counter { count: (c.count + 1) as u32, ..c }).inv(),
    {
    }
}

} // verus!
