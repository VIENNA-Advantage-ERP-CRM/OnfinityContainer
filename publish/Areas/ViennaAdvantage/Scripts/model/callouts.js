/** 
  *    Sample Class for Callout
       MPC--> refers to Module Prefix Code
  */
/*Module Name space initialization*/
; MPC = window.MPC || {};

; (function (MPC, $) {

    var Level = VIS.Logging.Level;
    var Util = VIS.Utility.Util;

    //1
    /* Sample Start */


    /**
    *  Callout Class
      -   must call this function
             VIS.CalloutEngine.call(this, [className]);
    */
    function TestClass() {
        VIS.CalloutEngine.call(this, "MPC.TestClass"); // must call base class (CalloutEngine)
    };
    /**
     * Inherit CalloutEngine Class 
     *VIS.Utility.inheritPrototype([Callout class Name], VIS.CalloutEngine)
     */
    VIS.Utility.inheritPrototype(TestClass, VIS.CalloutEngine);//must inheirt Base class CalloutEngine


    /**
     *  Callout function
     */
    TestClass.prototype.set = function (ctx, windowNo, mTab, mField, value, oldValue) {
        if (this.isCalloutActive() || value == null ) {
            return "";
        }
        this.setCalloutActive(true);
        mTab.setValue("Description", value);
        this.setCalloutActive(false);

        return "";

    };
    MPC.Model = MPC.Model || {};
    MPC.Model.TestClass = TestClass; //assign object in Model NameSpace

    /* Sample END */
})(MPC, jQuery);