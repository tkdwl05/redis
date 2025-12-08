start_server {tags {"list-custom"}} {
    test {LCOUNT basics} {
        r del mylist
        r rpush mylist 1 2 3 1 1 2
        assert_equal 3 [r lcount mylist 1]
        assert_equal 2 [r lcount mylist 2]
        assert_equal 1 [r lcount mylist 3]
        assert_equal 0 [r lcount mylist 4]
    }

    test {LCOUNT with non-existing key} {
        r del mylist
        assert_equal 0 [r lcount mylist 1]
    }

    test {LMAX basics} {
        r del mylist
        r rpush mylist 10 5 20 15
        assert_equal 20 [r lmax mylist]
    }

    test {LMAX with strings} {
        r del mylist
        r rpush mylist "abc" "z" "def"
        assert_equal "z" [r lmax mylist]
    }

    test {LMAX empty list} {
        r del mylist
        assert_equal {} [r lmax mylist]
    }

    test {LMIN basics} {
        r del mylist
        r rpush mylist 10 5 20 15
        assert_equal 5 [r lmin mylist]
    }

    test {LMIN with strings} {
        r del mylist
        r rpush mylist "abc" "z" "def"
        assert_equal "abc" [r lmin mylist]
    }

    test {LMIN empty list} {
        r del mylist
        assert_equal {} [r lmin mylist]
    }
}
