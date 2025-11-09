package com.example.ssf.dynamic;

import java.util.Objects;

public record DynamicCrudFilter(String column, String operator, Object value) {

    public DynamicCrudFilter {
        Objects.requireNonNull(column, "column is required");
        Objects.requireNonNull(operator, "operator is required");
    }
}
