package com.example.ssf.dynamic;

public record DynamicCrudAuditContext(
        String actor,
        String traceId,
        String clientIp,
        String metadata
) {
}
