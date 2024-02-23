package com.amazonaws.kafka.samples;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

public class TestCustomMM2ReplicationPolicy {

    @Test
    public void testCustomMM2ReplicationPolicy() {
        CustomMM2ReplicationPolicy customMM2ReplicationPolicy = new CustomMM2ReplicationPolicy();
        customMM2ReplicationPolicy.configure(new MM2Config().mm2config());
        assertEquals(customMM2ReplicationPolicy.formatRemoteTopic("", "ExampleTopic"), "ExampleTopic");
        assertEquals(customMM2ReplicationPolicy.topicSource("ExampleTopic"), "msksource");
        assertEquals(customMM2ReplicationPolicy.upstreamTopic("ExampleTopic"), null);
    }
}
