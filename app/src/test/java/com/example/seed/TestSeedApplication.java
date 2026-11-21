package com.example.seed;

import org.springframework.boot.SpringApplication;

public class TestSeedApplication {

	public static void main(String[] args) {
		SpringApplication.from(SeedApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
