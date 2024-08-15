/*!
 * PGXN JavaScript Library
 * https://pgxn.org/
 *
 * Copyright (c) 2010-2024 David E. Wheeler.
 *
 */

if (typeof PGXN == 'undefined') PGXN = {};

PGXN.ajax_click = function (e, obj, sel) {
    e.preventDefault();
    var tr   = $(obj).parents('tr');
    var form = $(obj).parents('form');
    $.ajax({
        type: 'POST',
        url: form.attr('action'),
        dataType: 'html',
        data: form.serialize(),
        beforeSend: function() {
			tr.children().css({'backgroundColor':'#fb6c6c'});
		},
        success: function () {
            tr.fadeOut(500, function() { tr.remove(); });
        },
        error: function (xhr) {
			tr.children().css({'backgroundColor':'transparent'});
            var err = jQuery(xhr.responseText);
            err.hide();
            $(sel).before(err);
            err.fadeIn(500);
        }
    });
};

PGXN.init_moderate = function () {
    $(document).ready(function() {
        $('.userplay').click(function (e) {
            $('.userplay').next().fadeOut(100);
            var bub = $(this).next();
            bub.css({
                position:'absolute',
                // left:$(this).offset().left - 64,
                top:$(this).offset().top + 21
            }).toggle();
            bub.click(function () { $(this).hide() });
            e.stopPropagation();
        });

        $('.actions .button').click(function (e) {
            e.preventDefault();
            $('.userplay').next().fadeOut(100);
            PGXN.ajax_click(e, this, '#userlist');
        });

    });
};

PGXN.validate_form = function(form) {
    $(document).ready(function() {
        jQuery.validator.addMethod("rsync", function(value, element) {
            return this.optional( element ) || /^(?:rsync:\/\/)(?:(?:[^\]\[?\/<~#`!@$^&*()+=}|:";',>{ ]|%[0-9A-Fa-f]{2})+(?::(?:[^\]\[?\/<~#`!@$^&*()+=}|:";',>{ ]|%[0-9A-Fa-f]{2})*)?@)?(?:(?!(?:10|127)(?:\.\d{1,3}){3})(?!(?:169\.254|192\.168)(?:\.\d{1,3}){2})(?!172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:1?\d{1,2}|2[0-4]\d|25[0-5])){2}(?:\.(?:[1-9]\d?|1\d\d|2[0-4]\d|25[0-4]))|(?:(?:[a-z0-9\u00a1-\uffff][a-z0-9\u00a1-\uffff_-]{0,62})?[a-z0-9\u00a1-\uffff]\.)+(?:[a-z\u00a1-\uffff]{2,}\.?)|(?:(?:[a-z0-9\u00a1-\uffff][a-z0-9\u00a1-\uffff_-]{0,62})?[a-z0-9\u00a1-\uffff])|(?:(?:[a-z0-9\u00a1-\uffff][a-z0-9\u00a1-\uffff_-]{0,62}\.)))(?::\d{2,5})?(?:[/?#]\S*)?$/i.test( value );
        }, "Please specify a valid rsync URL");

        $(form).validate({
            errorClass: 'invalid',
            wrapper: 'div',
            highlight: function(e) {
                $(e).addClass('highlight');
                $(e.form).find('label[for=' + e.id + ']').addClass('highlight');
            },
            unhighlight: function(e) {
                $(e).removeClass('highlight');
                $(e.form).find('label[for=' + e.id + ']').removeClass('highlight');
            },
            errorPlacement: function (er, el) { $(el).before(er) }
        });
    });
};

PGXN.init_mirrors = function () {
    $(document).ready(function() {
        $('.actions .button').click(function (e) { PGXN.ajax_click(e, this, '#mirrorlist') });
    });
};
