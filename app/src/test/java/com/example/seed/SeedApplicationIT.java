package com.example.seed;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;

@Import(TestcontainersConfiguration.class)
@SpringBootTest
class SeedApplicationIT {

	@Autowired
	JdbcTemplate jdbcTemplate;

	@Test
	void contextLoads() {
		assertThat(jdbcTemplate.queryForObject("SHOW server_version", String.class)).startsWith("18.2");
	}

}
