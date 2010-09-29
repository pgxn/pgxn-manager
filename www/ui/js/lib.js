/*!
 * PGXN JavaScript Library
 * http://pgxn.org/
 *
 * Copyright 2010, David E. Wheeler. Some Rights Reserved.
 *
 */

PGXN = {
    init_moderate: function () {
        $(document).ready(function() {
            $('.userplay').click(function (e) {
                $('.userplay').next().fadeOut(100);
                var bub = $(this).next();
                bub.css({
                    position:'absolute',
                    left:$(this).offset().left - 20,
                    top:$(this).offset().top + 31
                }).toggle();
                bub.click(function () { $(this).hide() });
                e.stopPropagation();
            });

            $('.actions .button').click(function (e) {
                e.preventDefault();
                $('.userplay').next().fadeOut(100);
                var tr   = $(this).parents('tr');
                var form = $(this).parents('form');
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
                        $('#userlist').before(err);
                        err.fadeIn(500);
                    }
                });
            });

        });
    },

    validate_form: function(form) {
        $(document).ready(function() {
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
    }
};


 