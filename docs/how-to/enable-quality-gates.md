# Ativar os quality gates no app

O kit de configuração não altera o projeto Maven em `app/`. Sem a configuração dos gates no `app/pom.xml`, o harness roda com `QUALITY_GATES=optional` (`.harness`): build e suítes executam, e cada gate não configurado retorna **SKIP** com o motivo. SKIP não é PASS, e o `verify.sh` termina PARCIAL ([ADR-0003](../architecture/adr/0003-test-suites-and-quality-gates.md)).

Este guia descreve o que adicionar para que JaCoCo, PIT e ArchUnit executem de fato. Os [blocos prontos](#blocos-prontos-para-este-projeto) no fim deste guia já vêm com o pacote e a classe deste projeto: copie-os em vez de reescrevê-los.

## O que o harness procura

| Gate | Script | Exige em `app/pom.xml` | Sem isso |
|---|---|---|---|
| Unitários | `scripts/test/unit.sh` | Surefire (padrão do Spring Boot); classes `*Test` | Classes `*Tests` (padrão do Initializr) não executam; o script avisa |
| Arquitetura | `scripts/test/architecture.sh` | Execução Surefire `<id>architecture</id>`; classe `*ArchitectureTest` | SKIP (`optional`) ou FAIL (`required`) |
| Integração | `scripts/test/integration.sh` | `maven-failsafe-plugin` e propriedade `skipUnitTests`; classes `*IT` | SKIP ou FAIL |
| Cobertura | `scripts/quality/coverage.sh` | JaCoCo com as execuções `prepare-unit-agent`, `prepare-integration-agent`, `coverage-merge`, `coverage-report` e `coverage-check`; propriedade `app.mainClass` | SKIP ou FAIL |
| Mutação | `scripts/quality/mutation.sh` | `pitest-maven` com `targetClasses` em `feature/*/domain` e `feature/*/service`; propriedade `app.basePath` | SKIP ou FAIL |

## Passos

1. **Propriedades** em `<properties>`: `app.basePackage`, `app.basePath` e `app.mainClass` (pacote e classe `@SpringBootApplication` do app), `skipUnitTests` (`false`), `argLine` vazia e as versões de JaCoCo, PIT e ArchUnit.
2. **Plugins:** `maven-dependency-plugin` (execução `resolve-test-agent`, para o agent do Mockito), Surefire (`default-test` e `architecture`), Failsafe, JaCoCo e PIT, com as metas LINE ≥ 90%, BRANCH ≥ 90% e mutation score ≥ 90%.
3. **Dependências de teste:** ArchUnit, Testcontainers (PostgreSQL) e `junit-platform-launcher`.
4. **Classes de teste** em `app/src/test/java/<pacote>/`: `architecture/ArchitectureTest.java`, `TestcontainersConfiguration.java`, `<Main>IT.java` e `Test<Main>.java`, adaptadas do seed.
5. **Convenção de nomes:** renomeie `*Tests` para `*Test` (unitários) ou `*IT` (integração).
6. Troque `QUALITY_GATES=optional` por `QUALITY_GATES=required` no `.harness`. A partir daí, um gate não configurado reprova o `verify.sh`.
7. Verifique com `bash scripts/verify.sh` e `bash scripts/quality/mutation.sh`. A capacidade de rejeitar violações pode ser provada com `bash scripts/harness-tests/quality-gates.sh`.

Mudanças no `app/pom.xml` são mudanças de build: exigem autorização, e as metas não podem ser reduzidas para obter aprovação (AGENTS.md, seção 6).

## Blocos prontos para este projeto

Gerados para o pacote `com.example.seed` e a classe `SeedApplication`. Copie cada bloco para o lugar indicado e ajuste só o que o projeto não usar.

### 1. `app/pom.xml`: propriedades (dentro de `<properties>`)

```xml
		<!-- Ponto único de customização do pacote base (quality gates e scripts/quality/*.sh). -->
		<app.basePackage>com.example.seed</app.basePackage>
		<app.basePath>com/example/seed</app.basePath>
		<app.mainClass>SeedApplication</app.mainClass>
		<skipUnitTests>false</skipUnitTests>
		<argLine/>
		<!-- Quality gates: versões explícitas, não gerenciadas pelo parent Spring Boot. -->
		<jacoco.version>0.8.16</jacoco.version>
		<archunit.version>1.5.1</archunit.version>
		<pitest.version>1.30.1</pitest.version>
		<pitest-junit5-plugin.version>1.2.3</pitest-junit5-plugin.version>
		<!-- Preenchidas pelo prepare-agent do JaCoCo; vazias quando o JaCoCo não executa. -->
		<jacocoUnitArgLine/>
		<jacocoItArgLine/>
```

### 2. `app/pom.xml`: dependências de teste (dentro de `<dependencies>`)

Se o app não usa banco, omita as três dependências de Testcontainers.

```xml
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-testcontainers</artifactId>
			<scope>test</scope>
		</dependency>
		<dependency>
			<groupId>org.testcontainers</groupId>
			<artifactId>testcontainers-junit-jupiter</artifactId>
			<scope>test</scope>
		</dependency>
		<dependency>
			<groupId>org.testcontainers</groupId>
			<artifactId>testcontainers-postgresql</artifactId>
			<scope>test</scope>
		</dependency>
		<dependency>
			<groupId>com.tngtech.archunit</groupId>
			<artifactId>archunit</artifactId>
			<version>${archunit.version}</version>
			<scope>test</scope>
		</dependency>
		<dependency>
			<groupId>org.junit.platform</groupId>
			<artifactId>junit-platform-launcher</artifactId>
			<scope>test</scope>
		</dependency>
```

### 3. `app/pom.xml`: plugins (dentro de `<build><plugins>`)

```xml
			<plugin>
				<groupId>org.apache.maven.plugins</groupId>
				<artifactId>maven-dependency-plugin</artifactId>
				<executions>
					<execution>
						<id>resolve-test-agent</id>
						<goals><goal>properties</goal></goals>
					</execution>
				</executions>
			</plugin>
			<plugin>
				<groupId>org.apache.maven.plugins</groupId>
				<artifactId>maven-surefire-plugin</artifactId>
				<configuration>
					<skipTests>${skipUnitTests}</skipTests>
					<failIfNoTests>true</failIfNoTests>
					<argLine>@{argLine} @{jacocoUnitArgLine} -javaagent:"${org.mockito:mockito-core:jar}"</argLine>
				</configuration>
				<executions>
					<execution>
						<id>default-test</id>
						<configuration>
							<includes><include>**/*Test.java</include></includes>
							<excludes><exclude>**/*ArchitectureTest.java</exclude></excludes>
						</configuration>
					</execution>
					<!-- ArchUnit: somente por execução explícita (surefire:test@architecture), relatórios próprios e sem agent JaCoCo. -->
					<execution>
						<id>architecture</id>
						<phase>none</phase>
						<goals><goal>test</goal></goals>
						<configuration>
							<includes><include>**/*ArchitectureTest.java</include></includes>
							<skipTests>false</skipTests>
							<reportsDirectory>${project.build.directory}/architecture-reports</reportsDirectory>
							<argLine>@{argLine}</argLine>
						</configuration>
					</execution>
				</executions>
			</plugin>
			<plugin>
				<groupId>org.apache.maven.plugins</groupId>
				<artifactId>maven-failsafe-plugin</artifactId>
				<configuration>
					<includes><include>**/*IT.java</include></includes>
					<failIfNoTests>true</failIfNoTests>
					<argLine>@{argLine} @{jacocoItArgLine} -javaagent:"${org.mockito:mockito-core:jar}"</argLine>
				</configuration>
				<executions>
					<execution>
						<goals>
							<goal>integration-test</goal>
							<goal>verify</goal>
						</goals>
					</execution>
				</executions>
			</plugin>
			<plugin>
				<groupId>org.jacoco</groupId>
				<artifactId>jacoco-maven-plugin</artifactId>
				<version>${jacoco.version}</version>
				<executions>
					<execution>
						<id>prepare-unit-agent</id>
						<goals><goal>prepare-agent</goal></goals>
						<configuration>
							<propertyName>jacocoUnitArgLine</propertyName>
							<destFile>${project.build.directory}/jacoco-unit.exec</destFile>
							<append>false</append>
						</configuration>
					</execution>
					<execution>
						<id>prepare-integration-agent</id>
						<goals><goal>prepare-agent-integration</goal></goals>
						<configuration>
							<propertyName>jacocoItArgLine</propertyName>
							<destFile>${project.build.directory}/jacoco-it.exec</destFile>
							<append>false</append>
						</configuration>
					</execution>
					<!-- Merge, relatório e check: somente por execução explícita (scripts/quality/coverage.sh). -->
					<execution>
						<id>coverage-merge</id>
						<phase>none</phase>
						<goals><goal>merge</goal></goals>
						<configuration>
							<fileSets>
								<fileSet>
									<directory>${project.build.directory}</directory>
									<includes>
										<include>jacoco-unit.exec</include>
										<include>jacoco-it.exec</include>
									</includes>
								</fileSet>
							</fileSets>
							<destFile>${project.build.directory}/jacoco-merged.exec</destFile>
						</configuration>
					</execution>
					<execution>
						<id>coverage-report</id>
						<phase>none</phase>
						<goals><goal>report</goal></goals>
						<configuration>
							<dataFile>${project.build.directory}/jacoco-merged.exec</dataFile>
							<outputDirectory>${project.build.directory}/site/jacoco</outputDirectory>
							<formats><format>XML</format><format>HTML</format></formats>
							<!-- Bootstrap Spring Boot sem regra de negócio; scripts/quality/coverage.sh lê as mesmas propriedades. -->
							<excludes>
								<exclude>${app.basePath}/${app.mainClass}.class</exclude>
							</excludes>
						</configuration>
					</execution>
					<execution>
						<id>coverage-check</id>
						<phase>none</phase>
						<goals><goal>check</goal></goals>
						<configuration>
							<dataFile>${project.build.directory}/jacoco-merged.exec</dataFile>
							<haltOnFailure>true</haltOnFailure>
							<excludes>
								<exclude>${app.basePath}/${app.mainClass}.class</exclude>
							</excludes>
							<rules>
								<rule>
									<element>BUNDLE</element>
									<limits>
										<limit>
											<counter>LINE</counter>
											<value>COVEREDRATIO</value>
											<minimum>0.90</minimum>
										</limit>
										<limit>
											<counter>BRANCH</counter>
											<value>COVEREDRATIO</value>
											<minimum>0.90</minimum>
										</limit>
									</limits>
								</rule>
							</rules>
						</configuration>
					</execution>
				</executions>
			</plugin>
			<plugin>
				<groupId>org.pitest</groupId>
				<artifactId>pitest-maven</artifactId>
				<version>${pitest.version}</version>
				<dependencies>
					<dependency>
						<groupId>org.pitest</groupId>
						<artifactId>pitest-junit5-plugin</artifactId>
						<version>${pitest-junit5-plugin.version}</version>
					</dependency>
				</dependencies>
				<configuration>
					<!-- Código de negócio elegível: domain e service das features; scripts/quality/mutation.sh lê app.basePath. -->
					<targetClasses>
						<param>${app.basePackage}.feature.*.domain.*</param>
						<param>${app.basePackage}.feature.*.service.*</param>
					</targetClasses>
					<targetTests>
						<param>${app.basePackage}.*Test</param>
					</targetTests>
					<excludedTestClasses>
						<param>${app.basePackage}.*ArchitectureTest</param>
					</excludedTestClasses>
					<mutationThreshold>90</mutationThreshold>
					<failWhenNoMutations>false</failWhenNoMutations>
					<timestampedReports>false</timestampedReports>
					<outputFormats>
						<param>XML</param>
						<param>HTML</param>
					</outputFormats>
					<jvmArgs>
						<jvmArg>-javaagent:${org.mockito:mockito-core:jar}</jvmArg>
					</jvmArgs>
				</configuration>
			</plugin>
```

### 4. Classes de teste em `app/src/test/java/com/example/seed/`

`architecture/ArchitectureTest.java`:

```java
package com.example.seed.architecture;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.library.dependencies.SlicesRuleDefinition.slices;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import com.tngtech.archunit.core.domain.Dependency;
import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.lang.ArchCondition;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.lang.ConditionEvents;
import com.tngtech.archunit.lang.SimpleConditionEvent;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Predicate;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.StreamSupport;
import org.junit.jupiter.api.Test;

/**
 * Regras derivadas de docs/architecture/dependency-rules.md, package-conventions.md e ADR-0001.
 *
 * <p>Uma regra sem classes elegíveis é ignorada (assumption) com o marcador {@value #NOT_APPLICABLE}: o
 * harness a reporta como N/A, nunca como aprovada (scripts/test/architecture.sh, ADR-0003).
 */
class ArchitectureTest {

	/** Prefixo das premissas de regras sem classes elegíveis, lido por scripts/test/architecture.sh. */
	static final String NOT_APPLICABLE = "[N/A] ";

	private static final String BASE = "com.example.seed";
	private static final String FEATURE = BASE + ".feature";
	private static final Pattern FEATURE_LAYER = Pattern.compile(Pattern.quote(FEATURE) + "\\.([^.]+)(?:\\.([^.]+))?.*");

	private static final String DOMAIN = FEATURE + ".*.domain..";
	private static final String API = FEATURE + ".*.api..";
	private static final String PERSISTENCE = FEATURE + ".*.persistence..";
	private static final String MESSAGING = FEATURE + ".*.messaging..";
	private static final String PRODUCER = FEATURE + ".*.messaging..producer..";
	private static final String CLIENT = FEATURE + ".*.client..";
	private static final String SERVICE = FEATURE + ".*.service..";

	private static final JavaClasses CLASSES = new ClassFileImporter()
			.withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
			.importPackages(BASE);

	@Test
	void domainDoesNotDependOnSpring() {
		checkWhenEligible("domain", inPackage("domain"), noClasses().that().resideInAPackage(DOMAIN)
				.should().dependOnClassesThat().resideInAPackage("org.springframework.."));
	}

	@Test
	void domainDoesNotDependOnHttpOrJdbc() {
		checkWhenEligible("domain", inPackage("domain"), noClasses().that().resideInAPackage(DOMAIN)
				.should().dependOnClassesThat().resideInAnyPackage(
						"jakarta.servlet..", "java.net.http..", "java.sql..", "javax.sql.."));
	}

	@Test
	void domainDoesNotDependOnApiPersistenceMessagingOrClients() {
		checkWhenEligible("domain", inPackage("domain"), noClasses().that().resideInAPackage(DOMAIN)
				.should().dependOnClassesThat().resideInAnyPackage(API, PERSISTENCE, MESSAGING, CLIENT));
	}

	@Test
	void apiDoesNotAccessPersistence() {
		checkWhenEligible("api", inPackage("api"), noClasses().that().resideInAPackage(API)
				.should().dependOnClassesThat().resideInAPackage(PERSISTENCE));
	}

	/** dependency-rules.md: a única dependência permitida de api dentro da feature é service. */
	@Test
	void apiDoesNotDependOnDomain() {
		checkWhenEligible("api", inPackage("api"), noClasses().that().resideInAPackage(API)
				.should().dependOnClassesThat().resideInAPackage(DOMAIN));
	}

	@Test
	void apiDoesNotExecuteSql() {
		checkWhenEligible("api", inPackage("api"), noClasses().that().resideInAPackage(API)
				.should().dependOnClassesThat().resideInAnyPackage(
						"java.sql..", "javax.sql..", "org.springframework.jdbc.."));
	}

	@Test
	void producersDoNotDependOnControllersOrServices() {
		checkWhenEligible("messaging producer", javaClass -> javaClass.getPackageName().matches(
				Pattern.quote(FEATURE) + "\\.[^.]+\\.messaging\\..*producer(\\..*)?"),
				noClasses().that().resideInAPackage(PRODUCER)
						.should().dependOnClassesThat().resideInAnyPackage(API, SERVICE));
	}

	@Test
	void persistenceTechnologyIsNotJpa() {
		checkWhenEligible("código principal", javaClass -> true, noClasses().that().resideInAPackage(BASE + "..")
				.should().dependOnClassesThat().resideInAnyPackage(
						"jakarta.persistence..", "org.springframework.data.jpa..", "org.hibernate.."));
	}

	@Test
	void featuresAreFreeOfCycles() {
		assumeTrue(features().size() >= 2, NOT_APPLICABLE + "Sem classes elegíveis: são necessárias ao menos duas features.");
		slices().matching(FEATURE + ".(*)..").should().beFreeOfCycles().check(CLASSES);
	}

	@Test
	void featureLayersAreFreeOfCycles() {
		boolean eligible = layersByFeature().values().stream().anyMatch(layers -> layers.size() >= 2);
		assumeTrue(eligible, NOT_APPLICABLE + "Sem classes elegíveis: nenhuma feature possui ao menos dois packages internos.");
		slices().matching(FEATURE + ".(*).(*)..").should().beFreeOfCycles().check(CLASSES);
	}

	@Test
	void featuresDoNotAccessPersistenceOfOtherFeatures() {
		assumeTrue(features().size() >= 2 && stream().anyMatch(inPackage("persistence")),
				NOT_APPLICABLE + "Sem classes elegíveis: são necessárias duas features e ao menos uma classe de persistence.");
		classes().that().resideInAPackage(FEATURE + "..").should(notDependOnPersistenceOfAnotherFeature())
				.check(CLASSES);
	}

	private static void checkWhenEligible(String scope, Predicate<JavaClass> eligible, ArchRule rule) {
		assumeTrue(stream().anyMatch(eligible), NOT_APPLICABLE + "Sem classes elegíveis em " + scope + ".");
		rule.check(CLASSES);
	}

	private static Predicate<JavaClass> inPackage(String layer) {
		return javaClass -> layerOf(javaClass.getPackageName()).filter(layer::equals).isPresent();
	}

	private static java.util.stream.Stream<JavaClass> stream() {
		return StreamSupport.stream(CLASSES.spliterator(), false);
	}

	private static Set<String> features() {
		return stream().map(javaClass -> featureOf(javaClass.getPackageName()))
				.flatMap(Optional::stream).collect(Collectors.toSet());
	}

	private static Map<String, Set<String>> layersByFeature() {
		return stream().filter(javaClass -> layerOf(javaClass.getPackageName()).isPresent())
				.collect(Collectors.groupingBy(javaClass -> featureOf(javaClass.getPackageName()).orElseThrow(),
						Collectors.mapping(javaClass -> layerOf(javaClass.getPackageName()).orElseThrow(),
								Collectors.toSet())));
	}

	private static Optional<String> featureOf(String packageName) {
		Matcher matcher = FEATURE_LAYER.matcher(packageName);
		return matcher.matches() ? Optional.of(matcher.group(1)) : Optional.empty();
	}

	private static Optional<String> layerOf(String packageName) {
		Matcher matcher = FEATURE_LAYER.matcher(packageName);
		return matcher.matches() ? Optional.ofNullable(matcher.group(2)) : Optional.empty();
	}

	private static ArchCondition<JavaClass> notDependOnPersistenceOfAnotherFeature() {
		return new ArchCondition<>("not depend on the persistence of another feature") {
			@Override
			public void check(JavaClass origin, ConditionEvents events) {
				Optional<String> originFeature = featureOf(origin.getPackageName());
				for (Dependency dependency : origin.getDirectDependenciesFromSelf()) {
					String targetPackage = dependency.getTargetClass().getPackageName();
					Optional<String> targetFeature = featureOf(targetPackage);
					boolean otherFeaturePersistence = targetFeature.isPresent()
							&& !targetFeature.equals(originFeature)
							&& layerOf(targetPackage).filter("persistence"::equals).isPresent();
					if (otherFeaturePersistence) {
						events.add(SimpleConditionEvent.violated(dependency, dependency.getDescription()));
					}
				}
			}
		};
	}

}
```

`TestcontainersConfiguration.java`:

```java
package com.example.seed;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

	@Bean
	@ServiceConnection
	public PostgreSQLContainer postgresContainer() {
		// Official postgres:18.2, pinned by digest; Testcontainers 2.0.x needs explicit compatibility.
		return new PostgreSQLContainer(DockerImageName.parse(
				"postgres@sha256:a688ae5c99f86c1424e046ace0de890608cc0ddb5ec8ef72a6ff8305fdc8f4d2")
				.asCompatibleSubstituteFor("postgres"));
	}

}
```

`SeedApplicationIT.java`:

```java
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
```

`TestSeedApplication.java`:

```java
package com.example.seed;

import org.springframework.boot.SpringApplication;

public class TestSeedApplication {

	public static void main(String[] args) {
		SpringApplication.from(SeedApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
```

Sem banco, troque `SeedApplicationIT` por um teste de contexto sem Testcontainers e não crie `TestcontainersConfiguration` nem `TestSeedApplication`:

```java
package com.example.seed;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class SeedApplicationIT {

	@Test
	void contextLoads() {
	}

}
```

### 5. Ativar

Com os blocos aplicados e `bash scripts/verify.sh` verde, troque `QUALITY_GATES=optional` por `QUALITY_GATES=required` no `.harness`.
