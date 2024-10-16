package com.example;

import org.bouncycastle.crypto.fips.FipsStatus;
import org.bouncycastle.crypto.CryptoServicesRegistrar;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;

@WebServlet(name = "SimpleFIPSTest", urlPatterns = { "/" })
public class SimpleFIPSTest extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("text/html");
        PrintWriter out = response.getWriter();
        
        // Generate HTML output for FIPS status
        out.println("<html><body>");
        
        if (!FipsStatus.isReady()) {
            out.println("<h2>FIPS status is not ready</h2>");
        } else {
            out.println("<h2>FIPS status of BCFIPS is ready</h2>");
            boolean isApprovedOnly = CryptoServicesRegistrar.isInApprovedOnlyMode();
            if (isApprovedOnly) {
                out.println("<p>Bouncy Castle is in approved-only mode.</p>");
            } else {
                out.println("<p>Bouncy Castle is not in approved-only mode.</p>");
            }
        }
        
        out.println("</body></html>");
    }
}
