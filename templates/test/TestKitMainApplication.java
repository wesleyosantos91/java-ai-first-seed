package com.example.kitapp;

import org.springframework.boot.SpringApplication;

public class TestKitMainApplication {

	public static void main(String[] args) {
		SpringApplication.from(KitMainApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
