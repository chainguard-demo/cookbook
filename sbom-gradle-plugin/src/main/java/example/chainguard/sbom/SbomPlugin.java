package example.chainguard.sbom;

import java.io.File;
import java.util.Collections;

import org.gradle.api.Plugin;
import org.gradle.api.Project;

/**
 * Registers the {@code chainguardSbom} extension and the {@code collectSboms}
 * task on the applying project.
 */
public class SbomPlugin implements Plugin<Project> {

    @Override
    public void apply(Project project) {
        SbomExtension ext = project.getExtensions().create("chainguardSbom", SbomExtension.class);
        ext.getOutputDirectory().convention(
                new File(project.getLayout().getBuildDirectory().getAsFile().get(), "chainguard-sboms"));
        ext.getFormats().convention(Collections.emptyList());
        ext.getConfiguration().convention("runtimeClasspath");
        ext.getSkip().convention(false);

        project.getTasks().register("collectSboms", CollectSbomsTask.class, task -> {
            task.setGroup("verification");
            task.setDescription("Fetch Chainguard SBOM sidecars for resolved dependencies.");
            task.getOutputDirectory().set(ext.getOutputDirectory());
            task.getFormats().set(ext.getFormats());
            task.getConfigurationName().set(ext.getConfiguration());
            task.getSkip().set(ext.getSkip());
        });
    }
}
