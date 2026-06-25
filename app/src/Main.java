public class Main {
    public static void main(String[] args) {
        System.out.println("✅ Java app.jar started successfully!");
        System.out.println("Arguments:");
        for (int i = 0; i < args.length; i++) {
            System.out.println("  arg[" + i + "] = " + args[i]);
        }

        try {
            // Simulate some long-running process
            Thread.sleep(10_000);
        } catch (InterruptedException e) {
            System.out.println("Interrupted, shutting down.");
        }
    }
}
