
// Reports.java --
//
// Reports.java is part of ElectricCommander.
//
// Copyright (c) 2005-2012 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.defectTracking.client;

import java.util.HashMap;
import java.util.Map;

import org.jetbrains.annotations.NonNls;

import com.google.gwt.event.dom.client.ClickEvent;
import com.google.gwt.event.dom.client.ClickHandler;
import com.google.gwt.http.client.Request;
import com.google.gwt.http.client.RequestCallback;
import com.google.gwt.http.client.RequestException;
import com.google.gwt.http.client.Response;
import com.google.gwt.user.client.Window.Location;
import com.google.gwt.user.client.ui.Anchor;
import com.google.gwt.user.client.ui.Button;
import com.google.gwt.user.client.ui.DecoratorPanel;
import com.google.gwt.user.client.ui.HTML;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.VerticalPanel;
import com.google.gwt.user.client.ui.Widget;

import com.electriccloud.commander.client.domain.Property;
import com.electriccloud.commander.client.domain.PropertySheet;
import com.electriccloud.commander.client.requests.GetPropertiesRequest;
import com.electriccloud.commander.client.requests.RunProcedureRequest;
import com.electriccloud.commander.client.responses.CommanderError;
import com.electriccloud.commander.client.responses.PropertySheetCallback;
import com.electriccloud.commander.client.responses.RunProcedureResponse;
import com.electriccloud.commander.client.responses.RunProcedureResponseCallback;
import com.electriccloud.commander.gwt.client.ComponentBase;
import com.electriccloud.commander.gwt.client.ComponentBaseFactory;
import com.electriccloud.commander.gwt.client.protocol.xml.RequestSerializerImpl;
import com.electriccloud.commander.gwt.client.requests.CgiRequestProxy;
import com.electriccloud.commander.gwt.client.ui.FormTable;
import com.electriccloud.commander.gwt.client.ui.SimpleErrorBox;
import com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder;

/**
 */
public class Reports
    extends ComponentBase
{

    //~ Methods ----------------------------------------------------------------

    @Override public Widget doInit()
    {

        /* Renders the component. */
        DecoratorPanel rootPanel = new DecoratorPanel();
        VerticalPanel  vPanel    = new VerticalPanel();

        vPanel.setBorderWidth(0);

        String              jobId      = getGetParameter("jobId");
        CommanderUrlBuilder urlBuilder = CommanderUrlBuilder.createUrl(
                                                                "jobDetails.php")
                                                            .setParameter(
                                                                "jobId", jobId);

        // noinspection HardCodedStringLiteral,StringConcatenation
        vPanel.add(new Anchor("Job: " + jobId, urlBuilder.buildString()));

        Widget htmlH1 = new HTML("<h1>CQ Defects</h1>");

        vPanel.add(htmlH1);

        // Label label = new Label("CQ defects associated with the
        // ElectricCommander job:");
        Widget htmlLabel = new HTML(
                "<p><b>CQ defects associated with the ElectricCommander job:</b></p>");

        vPanel.add(htmlLabel);

        FormTable formTable = getUIFactory().createFormTable();

        callback("defectLinks", formTable);
        vPanel.add(formTable.getWidget());
        vPanel.add(new HTML(
                "<p><b>CQ updated defects associated with the ElectricCommander job:</b></p>"));

        FormTable formTableUpdated = getUIFactory().createFormTable();

        callback("updatedDefectLinks", formTableUpdated);
        vPanel.add(formTableUpdated.getWidget());
        vPanel.add(new HTML(
                "<p><b>CQ created defects associated with the ElectricCommander job:</b></p>"));

        FormTable formTableCreated = getUIFactory().createFormTable();

        callback("createdDefectLinks", formTableCreated);
        vPanel.add(formTableCreated.getWidget());
        rootPanel.add(vPanel);

        return rootPanel;
    }

    @SuppressWarnings("OverlyComplexAnonymousInnerClass")
    private void callback(
            @NonNls final String propertyName,
            final FormTable      formTable)
    {
        final String jobId = getGetParameter("jobId");

        if (getLog().isDebugEnabled()) {
            getLog().debug("this is getGetParameter for jobId: "
                    + getGetParameter("jobId"));
            getLog().debug("this is jobId: " + jobId);
        }

        GetPropertiesRequest req = getRequestFactory()
                .createGetPropertiesRequest();

        // "defectLinks"
        req.setPath("/jobs/" + jobId + "/" + propertyName);

        if (getLog().isDebugEnabled()) {
            getLog().debug(
                "CQ Reports doInit: setting up getProperties command request");
        }

        req.setCallback(new PropertySheetCallback() {
                @Override public void handleResponse(PropertySheet response)
                {

                    if ("createdDefectLinks".equals(propertyName)) {
                        parseResponseCreatedDefects(response, formTable, jobId);
                    }
                    else {
                        parseResponse(response, formTable);
                    }
                }

                @Override public void handleError(CommanderError error)
                {

                    if (getLog().isDebugEnabled()) {
                        getLog().debug("Error trying to access property");
                    }

                    // noinspection HardCodedStringLiteral
                    formTable.addRow("0", new Label("No Defects Found"));
                }
            });

        if (getLog().isDebugEnabled()) {
            getLog().debug("CQ Reports doInit: Issuing Commander request: "
                    + new RequestSerializerImpl().serialize(req));
        }

        doRequest(req);
    }

    /**
     * Helper for handling created-defects properties with a "prop" get param in
     * the prop value.
     *
     * @param  form
     * @param  jobId
     * @param  p
     */
    private void handleCreatedDefectsProp(
            FormTable    form,
            final String jobId,
            Property     p)
    {
        @NonNls String value = p.getValue();

        assert value != null;

        String prop = value.substring(value.indexOf("?prop="));

        if (getLog().isDebugEnabled()) {
            getLog().debug("Prop:" + prop);
        }

        prop = prop.substring(prop.indexOf('=') + 1);

        if (getLog().isDebugEnabled()) {
            getLog().debug("Prop2:" + prop);
        }

        value = value.substring(0, value.indexOf("?prop="));

        if (getLog().isDebugEnabled()) {
            getLog().debug("Value:" + value);
        }

        final String propertyFinal = prop;

        // final String jobIDFinal = jobId;
        final Button fileDefectButton = new Button();

        fileDefectButton.setHTML("File Defect");
        fileDefectButton.addClickHandler(new ClickHandler() {
                @Override
                @SuppressWarnings("OverlyComplexAnonymousInnerClass")
                public void onClick(ClickEvent event)
                {
                    fileDefectButton.setEnabled(false);

                    // Build runProcedure request
                    RunProcedureRequest request = getRequestFactory()
                            .createRunProcedureRequest();

                    request.setProjectName(
                            "/plugins/EC-DefectTracking-CQ/project")
                        .setProcedureName("FileDefectProcedure")
                        .addActualParameter("propProc", propertyFinal)
                        .addActualParameter("jobIdParamProc", jobId)
                        .setCallback(new RunProcedureResponseCallback() {
                                @Override public void handleResponse(
                                        RunProcedureResponse response)
                                {

                                    if (getLog().isDebugEnabled()) {
                                        getLog().debug(
                                            "Commander runProcedure request returned job "
                                            + response.getJobId());
                                    }

                                    waitForJob(response.getJobId().toString());
                                }

                                @Override public void handleError(
                                        CommanderError error)
                                {

                                    if (getLog().isDebugEnabled()) {
                                        getLog().debug(
                                            "Commander ERROR runProcedure request returned: "
                                            + error);
                                    }
                                }
                            });

                    if (getLog().isDebugEnabled()) {
                        getLog().debug("Issuing Commander request: "
                                + request);
                    }

                    doRequest(request);
                }
            });
        form.addRow("0", new Label(p.getName() + value), fileDefectButton);
    }

    private void parseResponse(
            PropertySheet response,
            FormTable     form)
    {

        if (getLog().isDebugEnabled()) {
            getLog().debug("getProperties request returned "
                    + response.getProperties()
                              .size() + " properties");
        }

        for (Property p : response.getProperties()
                                  .values()) {
            Anchor anchor = new Anchor(p.getName(), p.getValue());

            form.addRow("0", anchor);

            if (getLog().isDebugEnabled()) {
                getLog().debug("  propertyName="
                        + p.getName()
                        + ", value=" + p.getValue());
            }
        }
    }

    private void parseResponseCreatedDefects(
            PropertySheet response,
            FormTable     form,
            String        jobId)
    {

        if (getLog().isDebugEnabled()) {
            getLog().debug("getProperties request returned "
                    + response.getProperties()
                              .size() + " properties");
        }

        for (Property p : response.getProperties()
                                  .values()) {
            @NonNls String value = p.getValue();

            assert value != null;

            if (value.contains("?url=")) {
                String url = value.substring(value.indexOf("?url="));

                if (getLog().isDebugEnabled()) {
                    getLog().debug("URL:" + url);
                }

                url = url.substring(url.indexOf('=') + 1);

                if (getLog().isDebugEnabled()) {
                    getLog().debug("URL2:" + url);
                }

                value = value.substring(0, value.indexOf("?url="));

                if (getLog().isDebugEnabled()) {
                    getLog().debug("Value:" + value);
                }

                form.addRow("0", new Anchor(p.getName() + value, url));
            }
            else if (value.contains("?prop=")) {
                handleCreatedDefectsProp(form, jobId, p);
            }

            if (getLog().isDebugEnabled()) {
                getLog().debug("  propertyName="
                        + p.getName()
                        + ", value=" + value);
            }
        }
    }

    @SuppressWarnings("OverlyComplexAnonymousInnerClass")
    private void waitForJob(final String jobId)
    {
        CgiRequestProxy     cgiRequestProxy = new CgiRequestProxy(
                ComponentBaseFactory.getPluginName(), "monitorJob.cgi");
        Map<String, String> cgiParams       = new HashMap<String, String>();

        cgiParams.put("jobId", jobId);

        // Pass debug flag to CGI, which will use it to determine whether to
        // clean up a successful job
        if ("1".equals(getGetParameter("debug"))) {
            cgiParams.put("debug", "1");
        }

        try {
            cgiRequestProxy.issueGetRequest(cgiParams, new RequestCallback() {
                    @Override public void onError(
                            Request   request,
                            Throwable exception)
                    {

                        if (getLog().isDebugEnabled()) {
                            getLog().debug(
                                "CGI request failed: "
                                    + exception.getMessage());
                        }
                    }

                    @Override public void onResponseReceived(
                            Request  request,
                            Response response)
                    {
                        String responseString = response.getText();

                        if (getLog().isDebugEnabled()) {
                            getLog().debug(
                                "CGI response received: " + responseString);
                        }

                        if (responseString.startsWith("Success")) {

                            // We're done!
                            Location.reload();
                        }
                        else {
                            @SuppressWarnings(
                                {
                                    "HardCodedStringLiteral",
                                    "StringConcatenation"
                                }
                            )
                            SimpleErrorBox      error      = getUIFactory()
                                    .createSimpleErrorBox(
                                        "Error occurred during File Defect: "
                                        + responseString);
                            CommanderUrlBuilder urlBuilder = CommanderUrlBuilder
                                    .createUrl("jobDetails.php")
                                    .setParameter("jobId", jobId);

                            // noinspection HardCodedStringLiteral
                            error.add(
                                new Anchor("(See job for details)",
                                    urlBuilder.buildString()));

                            if (getLog().isDebugEnabled()) {
                                getLog().debug(
                                    "Error occurred during File Defect");
                            }
                        }
                    }
                });
        }
        catch (RequestException e) {

            if (getLog().isDebugEnabled()) {
                getLog().debug("CGI request failed: " + e.getMessage());
            }
        }
    }
}
